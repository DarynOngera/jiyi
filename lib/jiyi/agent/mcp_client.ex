defmodule Jiyi.Agent.MCPClient do
  @behaviour Jiyi.Agent.Client

  alias Jiyi.Agent.Config
  alias Jiyi.Agent.Tools

  @impl true
  def init(%Config{} = config) do
    transport = transport_config(config)
    name = via_name(config.agent_id)
    transport_name = via_transport_name(config.agent_id)

    opts = [
      name: name,
      transport_name: transport_name,
      transport: transport,
      client_info: %{"name" => "jiyi-agent", "version" => "0.1.0"},
      capabilities: %{},
      protocol_version: "2025-03-26"
    ]

    case Anubis.Client.start_link(opts) do
      {:ok, pid} ->
        :ok = Anubis.Client.await_ready(name, timeout: 15_000)
        {:ok, %{name: name, pid: pid, session_token: config.api_key}}

      error ->
        error
    end
  end

  @impl true
  def context_assemble(%{name: name, session_token: token}, request) do
    args =
      %{
        "agent_id" => request["agent_id"],
        "session_id" => request["session_id"],
        "task" => request["task"],
        "token_budget" => request["token_budget"],
        "memory_scopes" => request["memory_scopes"],
        "session_token" => token
      }
      |> drop_nil()

    case Anubis.Client.call_tool(name, "context_assemble", args) do
      {:ok, %Anubis.MCP.Response{result: result}} -> unwrap_tool_result(result)
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def memory_write(%{name: name, session_token: token}, request) do
    args =
      %{
        "type" => request["type"],
        "agent_id" => request["agent_id"],
        "session_id" => request["session_id"],
        "content" => request["content"],
        "provenance" => request["provenance"],
        "scope" => request["scope"],
        "session_token" => token
      }
      |> drop_nil()

    case Anubis.Client.call_tool(name, "memory_write", args) do
      {:ok, %Anubis.MCP.Response{result: result}} -> unwrap_tool_result(result)
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def tools, do: [Tools.context_assemble(), Tools.memory_write()]

  def transport_config(%{transport: :mcp_http, endpoint: endpoint}) do
    uri = URI.parse(endpoint)
    base_url = "#{uri.scheme}://#{uri.host}:#{uri.port}"
    mcp_path = uri.path || "/"

    {:streamable_http, base_url: base_url, mcp_path: mcp_path, enable_sse: true}
  end

  def transport_config(%{transport: :mcp_stdio}) do
    cwd = File.cwd!()

    {:stdio,
     command: "elixir",
     args: ["-S", "mix", "run", "--no-halt"],
     cwd: cwd,
     env: %{
       "JIYI_HTTP_PORT" => "0",
       "JIYI_MCP_TRANSPORT" => "stdio"
     }}
  end

  defp via_name(agent_id) do
    {:via, Registry, {Jiyi.Registry, {__MODULE__, agent_id}}}
  end

  defp via_transport_name(agent_id) do
    {:via, Registry, {Jiyi.Registry, {__MODULE__, :Transport, agent_id}}}
  end

  defp drop_nil(map) do
    Enum.reject(map, fn {_key, value} -> is_nil(value) end) |> Map.new()
  end

  defp unwrap_tool_result(%{"content" => [%{"type" => "text", "text" => text} | _]} = result) do
    case Jason.decode(text) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:ok, result}
    end
  end

  defp unwrap_tool_result(result), do: {:ok, result}
end
