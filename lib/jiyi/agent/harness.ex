defmodule Jiyi.Agent.Harness do
  use GenServer

  alias Jiyi.Agent.Config
  alias Jiyi.Agent.{HTTPClient, MCPClient, Prompt}

  @stopwords MapSet.new([
               "a",
               "an",
               "the",
               "and",
               "or",
               "but",
               "is",
               "are",
               "was",
               "were",
               "be",
               "been",
               "being",
               "have",
               "has",
               "had",
               "do",
               "does",
               "did",
               "will",
               "would",
               "could",
               "should",
               "may",
               "might",
               "must",
               "can",
               "this",
               "that",
               "these",
               "those",
               "i",
               "you",
               "he",
               "she",
               "it",
               "we",
               "they",
               "me",
               "him",
               "her",
               "us",
               "them",
               "my",
               "your",
               "his",
               "its",
               "our",
               "their",
               "of",
               "in",
               "on",
               "at",
               "to",
               "for",
               "with",
               "about",
               "as",
               "by",
               "from"
             ])

  defstruct [:config, :client, :client_state, :messages, last_task: nil]

  def start_link(%Config{} = config, opts \\ []) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def run(pid, task) do
    GenServer.call(pid, {:run, task}, 120_000)
  end

  @impl true
  def init(%Config{} = config) do
    {client_mod, state} = init_client(config)

    {:ok,
     %__MODULE__{
       config: config,
       client: client_mod,
       client_state: state,
       messages: [],
       last_task: nil
     }}
  end

  @impl true
  def handle_call({:run, task}, _from, state) do
    task = if is_binary(task), do: task, else: to_string(task)

    with :ok <- write_working_memory(state, %{active_task: task}),
         :ok <- write_working_memory(state, %{recent_tool_outputs: []}),
         {:ok, context} <- assemble_context(state, task) do
      context = maybe_merge_shifted_context(state, task, context)

      llm_config = build_llm_config(state, context)
      messages = state.messages ++ [%{role: "user", content: task}]
      tools = state.client.tools()

      case llm_module(state.config).chat(messages, tools, llm_config) do
        {:ok, %{tool_calls: []} = result} ->
          new_messages = messages ++ [%{role: "assistant", content: result.content}]

          {:reply, {:ok, result.content}, %{state | messages: new_messages, last_task: task}}

        {:ok, %{tool_calls: calls} = result} when is_list(calls) and calls != [] ->
          {tool_messages, post_write_context} = execute_tool_calls(calls, state, context)

          follow_up =
            messages ++ [%{role: "assistant", content: result.content}] ++ tool_messages

          follow_up_config = build_llm_config(state, post_write_context)

          case llm_module(state.config).chat(follow_up, tools, follow_up_config) do
            {:ok, %{content: content}} ->
              final_messages = follow_up ++ [%{role: "assistant", content: content}]

              {:reply, {:ok, content}, %{state | messages: final_messages, last_task: task}}

            {:error, reason} ->
              {:reply, {:error, reason}, %{state | last_task: task}}
          end

        {:ok, result} ->
          {:reply, {:ok, result.content}, %{state | messages: messages, last_task: task}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
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

  defp build_llm_config(state, context) do
    base = state.config.llm || %{}

    Map.merge(base, %{
      api_key: nested_get(state.config.llm, [:api_key]),
      model: nested_get(state.config.llm, [:model]),
      max_tokens: nested_get(state.config.llm, [:max_tokens]),
      system_prompt: Prompt.build(state.config, context)
    })
  end

  defp assemble_context(state, task) do
    assemble_request = %{
      "task" => task,
      "token_budget" => state.config.token_budget,
      "memory_scopes" => state.config.scopes
    }

    state.client.context_assemble(state.client_state, assemble_request)
  end

  defp maybe_merge_shifted_context(state, task, context) do
    if task_shifted?(state.last_task, task) do
      assemble_request = %{
        "task" => task,
        "token_budget" => state.config.token_budget,
        "memory_scopes" => state.config.scopes
      }

      case state.client.context_assemble(state.client_state, assemble_request) do
        {:ok, shifted_context} ->
          merge_context(context, shifted_context)

        {:error, _reason} ->
          context
      end
    else
      context
    end
  end

  defp task_shifted?(nil, _task), do: false

  defp task_shifted?(last_task, task)
       when is_binary(last_task) and is_binary(task) do
    last_tokens = task_tokens(last_task)
    current_tokens = task_tokens(task)

    if map_size(last_tokens) == 0 or map_size(current_tokens) == 0 do
      false
    else
      overlap =
        Enum.count(current_tokens, fn {token, _} -> Map.has_key?(last_tokens, token) end)

      total = map_size(current_tokens)
      overlap / total < 0.4
    end
  end

  defp task_shifted?(_last_task, _task), do: false

  defp task_tokens(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&MapSet.member?(@stopwords, &1))
    |> Enum.reduce(%{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end

  defp merge_context(first, second) do
    first_text = context_text(first)
    second_text = context_text(second)

    merged_text =
      [first_text, second_text]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    sources = context_sources(first) ++ context_sources(second)
    deduped = Enum.uniq_by(sources, fn source -> source_id(source) end)

    put_context_fields(first, merged_text, deduped)
  end

  defp context_text(context) do
    Map.get(context, "assembled_context") || Map.get(context, :assembled_context) || ""
  end

  defp context_sources(context) do
    Map.get(context, "sources") || Map.get(context, :sources) || []
  end

  defp source_id(source) do
    Map.get(source, "id") || Map.get(source, :id)
  end

  defp put_context_fields(template, text, sources) do
    template
    |> Map.put("assembled_context", text)
    |> Map.put(:assembled_context, text)
    |> Map.put("sources", sources)
    |> Map.put(:sources, sources)
  end

  defp execute_tool_calls(calls, state, context) do
    {tool_messages, final_context, _last_written} =
      Enum.reduce(calls, {[], context, nil}, fn call, {messages, ctx, _written} ->
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

        tool_message = %{
          role: "user",
          content: "Tool result for #{call.name}: #{format_result(result)}"
        }

        {ctx, written} =
          case call.name do
            "memory_write" ->
              maybe_refresh_after_write(state, result, request, ctx)

            _ ->
              {ctx, nil}
          end

        {ctx, written} =
          if call.name not in ["memory_write", "context_assemble"] do
            summary = "Tool #{call.name} returned: #{result_summary(result)}"

            episodic_request = %{
              "type" => "episodic",
              "content" => %{"summary" => summary},
              "provenance" => %{
                "source" => "harness_hook",
                "ingestion_method" => "tool_result",
                "trust_tier" => "agent_derived"
              },
              "scope" => "agent_private",
              "session_id" => state.config.session_id
            }

            _ = state.client.memory_write(state.client_state, episodic_request)
            {ctx, nil}
          else
            {ctx, written}
          end

        {[tool_message | messages], ctx, written}
      end)

    {Enum.reverse(tool_messages), final_context}
  end

  defp maybe_refresh_after_write(state, result, request, context) do
    status = memory_write_status(result)

    if status in ["written", "duplicate"] do
      task = memory_write_task(request)

      refreshed_context =
        if task != "" do
          assemble_request = %{
            "task" => task,
            "token_budget" => state.config.token_budget,
            "memory_scopes" => state.config.scopes
          }

          case state.client.context_assemble(state.client_state, assemble_request) do
            {:ok, refreshed} -> merge_context(context, refreshed)
            {:error, _reason} -> context
          end
        else
          context
        end

      {refreshed_context, status}
    else
      {context, nil}
    end
  end

  defp memory_write_status({:ok, %{} = result}) do
    Map.get(result, "status") || Map.get(result, :status)
  end

  defp memory_write_status(_), do: nil

  defp memory_write_task(%{"type" => "semantic", "content" => content}) do
    subject = Map.get(content, "subject") || ""
    predicate = Map.get(content, "predicate") || ""
    object = Map.get(content, "object") || ""
    "#{subject} #{predicate} #{object}" |> String.trim()
  end

  defp memory_write_task(%{"type" => "episodic", "content" => content}) do
    Map.get(content, "summary") || "" |> String.trim()
  end

  defp memory_write_task(%{"type" => "working", "content" => content}) when is_map(content) do
    content
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> Enum.join(" ")
    |> String.trim()
  end

  defp memory_write_task(_), do: ""

  defp result_summary({:ok, %{} = result}) do
    Map.get(result, "status") || Map.get(result, :status) || "ok"
  end

  defp result_summary({:error, reason}), do: "error: #{inspect(reason)}"
  defp result_summary(_), do: "ok"

  defp write_working_memory(state, content) do
    request = %{
      "type" => "working",
      "content" => stringify_keys(content),
      "provenance" => %{
        "source" => "harness_hook",
        "ingestion_method" => "automatic",
        "trust_tier" => "agent_derived"
      },
      "scope" => "session_shared",
      "session_id" => state.config.session_id
    }

    case state.client.memory_write(state.client_state, request) do
      {:ok, _} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp format_result({:ok, value}), do: Jason.encode!(%{ok: value})
  defp format_result({:error, reason}), do: Jason.encode!(%{error: reason})
  defp format_result(value), do: inspect(value)

  defp llm_module(%Config{llm: %{module: module}}), do: module
  defp llm_module(%Config{}), do: raise(ArgumentError, "LLM adapter module is required")

  defp nested_get(nil, _path), do: nil
  defp nested_get(map, path), do: Kernel.get_in(map, path)
end
