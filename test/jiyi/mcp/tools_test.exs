defmodule Jiyi.MCP.ToolsTest do
  use Jiyi.DataCase

  alias Jiyi.MCP.Tools

  test "context_assemble/1 with valid token returns assembled context" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    {:ok, token} = Jiyi.Auth.issue_mcp_token(agent_id)

    assert {:ok, %{assembled_context: _, sources: _, token_count: _, blocked: false}} =
             Tools.context_assemble(%{
               "agent_id" => agent_id,
               "session_id" => "session-1",
               "task" => "investigate alert",
               "session_token" => token
             })
  end

  test "context_assemble/1 with invalid token returns error" do
    assert {:error, :invalid_token} =
             Tools.context_assemble(%{
               "agent_id" => "agent-1",
               "session_id" => "session-1",
               "task" => "investigate alert",
               "session_token" => "invalid-token"
             })
  end

  test "memory_write/1 with valid token returns written status" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    {:ok, token} = Jiyi.Auth.issue_mcp_token(agent_id)

    assert {:ok, %{status: "written", id: _}} =
             Tools.memory_write(%{
               "type" => "semantic",
               "agent_id" => agent_id,
               "session_id" => "session-1",
               "content" => %{"subject" => "project", "predicate" => "uses", "object" => "Elixir"},
               "provenance" => %{
                 "source" => "agent_inference",
                 "ingestion_method" => "direct_write",
                 "trust_tier" => "agent_derived"
               },
               "scope" => "session_shared",
               "session_token" => token
             })
  end

  test "memory_write/1 with expired token returns error" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    token = "expired-token-#{System.unique_integer([:positive])}"

    hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    %Jiyi.Schemas.McpSessionToken{}
    |> Jiyi.Schemas.McpSessionToken.changeset(%{
      token_hash: hash,
      agent_id: agent_id,
      expires_at: DateTime.add(DateTime.utc_now(), -1, :second),
      inserted_at: DateTime.utc_now()
    })
    |> Jiyi.Repo.insert!()

    assert {:error, :expired_token} =
             Tools.memory_write(%{
               "type" => "semantic",
               "agent_id" => agent_id,
               "content" => %{"subject" => "x", "predicate" => "y", "object" => "z"},
               "provenance" => %{
                 "source" => "agent_inference",
                 "ingestion_method" => "direct_write",
                 "trust_tier" => "agent_derived"
               },
               "scope" => "agent_private",
               "session_token" => token
             })
  end
end
