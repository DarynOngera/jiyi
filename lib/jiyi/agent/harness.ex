defmodule Jiyi.Agent.Harness do
  use GenServer

  alias Jiyi.Agent.Config
  alias Jiyi.Agent.{HTTPClient, MCPClient, Prompt}

  defstruct [:config, :client, :client_state, :messages]

  def start_link(%Config{} = config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def run(pid, task) do
    GenServer.call(pid, {:run, task}, 120_000)
  end

  @impl true
  def init(%Config{} = config) do
    {client_mod, state} = init_client(config)
    {:ok, %__MODULE__{config: config, client: client_mod, client_state: state, messages: []}}
  end

  @impl true
  def handle_call({:run, task}, _from, state) do
    assemble_request = %{
      "task" => task,
      "token_budget" => state.config.token_budget,
      "memory_scopes" => state.config.scopes
    }

    case state.client.context_assemble(state.client_state, assemble_request) do
      {:ok, context} ->
        llm_config = %{
          api_key: nested_get(state.config.llm, [:api_key]),
          model: nested_get(state.config.llm, [:model]),
          max_tokens: nested_get(state.config.llm, [:max_tokens]),
          system_prompt: Prompt.build(state.config, context)
        }

        messages = state.messages ++ [%{role: "user", content: task}]
        tools = state.client.tools()

        case llm_module(state.config).chat(messages, tools, llm_config) do
          {:ok, %{tool_calls: []} = result} ->
            new_messages = messages ++ [%{role: "assistant", content: result.content}]
            {:reply, {:ok, result.content}, %{state | messages: new_messages}}

          {:ok, %{tool_calls: calls} = result} when is_list(calls) and calls != [] ->
            tool_messages = execute_tool_calls(calls, state)

            follow_up =
              messages ++ [%{role: "assistant", content: result.content}] ++ tool_messages

            case llm_module(state.config).chat(follow_up, tools, llm_config) do
              {:ok, %{content: content}} ->
                final_messages = follow_up ++ [%{role: "assistant", content: content}]
                {:reply, {:ok, content}, %{state | messages: final_messages}}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end

          {:ok, result} ->
            {:reply, {:ok, result.content}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp init_client(%Config{transport: :http} = config) do
    {:ok, state} = HTTPClient.init(config)
    {HTTPClient, state}
  end

  defp init_client(%Config{transport: transport} = config)
       when transport in [:mcp_http, :mcp_stdio] do
    {:ok, state} = MCPClient.init(config)
    {MCPClient, state}
  end

  defp execute_tool_calls(calls, state) do
    Enum.map(calls, fn call ->
      request =
        call.arguments
        |> Map.put_new("agent_id", state.config.agent_id)
        |> Map.put_new("session_id", state.config.session_id)
        |> Map.put_new("org_id", state.config.org_id)

      result =
        case call.name do
          "memory_write" ->
            state.client.memory_write(state.client_state, request)

          "context_assemble" ->
            state.client.context_assemble(state.client_state, request)

          _ ->
            {:error, :unknown_tool}
        end

      %{role: "user", content: "Tool result for #{call.name}: #{format_result(result)}"}
    end)
  end

  defp format_result({:ok, value}), do: Jason.encode!(%{ok: value})
  defp format_result({:error, reason}), do: Jason.encode!(%{error: reason})
  defp format_result(value), do: inspect(value)

  defp llm_module(%Config{llm: %{module: module}}), do: module
  defp llm_module(%Config{}), do: raise(ArgumentError, "LLM adapter module is required")

  defp nested_get(nil, _path), do: nil
  defp nested_get(map, path), do: Kernel.get_in(map, path)
end
