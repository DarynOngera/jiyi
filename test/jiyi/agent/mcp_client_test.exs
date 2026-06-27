defmodule Jiyi.Agent.MCPClientTest do
  use Jiyi.DataCase

  alias Jiyi.Agent.{Config, MCPClient}

  setup do
    unless Process.whereis(Jiyi.API.Supervisor) do
      start_supervised!(Jiyi.API.Supervisor)
    end

    vector = List.duplicate(0.0, 768)
    :meck.expect(Jiyi.EmbeddingClient.CircuitBreaker, :embed, fn _ -> {:ok, vector} end)

    agent_id = "mcp-agent-#{System.unique_integer([:positive])}"
    {:ok, token} = issue_mcp_token(agent_id)

    on_exit(fn ->
      try do
        :meck.unload(Jiyi.EmbeddingClient.CircuitBreaker)
      rescue
        _ -> :ok
      end
    end)

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
        endpoint: "#{http_endpoint()}/mcp",
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

    {:streamable_http, opts} = Jiyi.Agent.MCP.AnubisAdapter.build_transport(config)

    assert opts[:base_url] == "http://localhost:4002"
    assert opts[:mcp_path] == "/mcp"
  end

  defp issue_mcp_token(agent_id) do
    url = "#{http_endpoint()}/auth/mcp-token"

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

  defp http_endpoint do
    port = Application.fetch_env!(:jiyi, :http_port)
    "http://localhost:#{port}"
  end
end
