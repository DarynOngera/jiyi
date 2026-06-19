defmodule Jiyi.Agent.MCPClientTest do
  use Jiyi.DataCase

  alias Jiyi.Agent.{Config, MCPClient}

  setup do
    unless Process.whereis(Jiyi.API.Supervisor) do
      start_supervised!(Jiyi.API.Supervisor)
    end

    agent_id = "mcp-agent-#{System.unique_integer([:positive])}"
    {:ok, token} = issue_mcp_token(agent_id)

    %{agent_id: agent_id, token: token}
  end

  test "writes and assembles memory over MCP streamable HTTP", %{
    agent_id: agent_id,
    token: token
  } do
    config =
      Config.new(
        agent_id: agent_id,
        session_id: "mcp-session",
        api_key: token,
        endpoint: "http://localhost:4001/mcp",
        transport: :mcp_http
      )

    {:ok, state} = MCPClient.init(config)

    assert {:ok, %{"status" => "written", "id" => _}} =
             MCPClient.memory_write(state, %{
               "type" => "semantic",
               "agent_id" => agent_id,
               "session_id" => "mcp-session",
               "content" => %{
                 "subject" => "project",
                 "predicate" => "uses",
                 "object" => "MCP"
               },
               "provenance" => %{
                 "source" => "agent_inference",
                 "ingestion_method" => "direct_write",
                 "trust_tier" => "agent_derived"
               },
               "scope" => "session_shared"
             })

    assert {:ok, %{"assembled_context" => context}} =
             MCPClient.context_assemble(state, %{
               "agent_id" => agent_id,
               "session_id" => "mcp-session",
               "task" => "What does the project use?",
               "memory_scopes" => ["session_shared"]
             })

    assert context =~ "MCP"
  end

  test "builds streamable_http transport config" do
    config =
      Config.new(
        agent_id: "a1",
        transport: :mcp_http,
        endpoint: "http://localhost:4002/mcp"
      )

    {:streamable_http, opts} = MCPClient.transport_config(config)

    assert opts[:base_url] == "http://localhost:4002"
    assert opts[:mcp_path] == "/mcp"
  end

  defp issue_mcp_token(agent_id) do
    url = "http://localhost:4001/auth/mcp-token"

    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer test-token"}
    ]

    body = Jason.encode!(%{agent_id: agent_id})

    {:ok, %{status: 200, body: resp}} =
      Finch.build(:post, url, headers, body) |> Finch.request(Jiyi.Finch)

    {:ok, %{"token" => token}} = Jason.decode(resp)
    {:ok, token}
  end
end
