defmodule Jiyi.Agent.MCPClient do
  @behaviour Jiyi.Agent.Client

  alias Jiyi.Agent.Config
  alias Jiyi.Agent.Tools

  @impl true
  def init(%Config{} = config) do
    transport = adapter().build_transport(config)
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

    case adapter().start_link(opts) do
      {:ok, pid} ->
        :ok = adapter().await_ready(name, 15_000)
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

    adapter().call_tool(name, "context_assemble", args)
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

    adapter().call_tool(name, "memory_write", args)
  end

  @impl true
  def tools, do: [Tools.context_assemble(), Tools.memory_write()]

  defp adapter do
    Application.get_env(:jiyi, :mcp_client_adapter, Jiyi.Agent.MCP.AnubisAdapter)
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
end
