defmodule Jiyi.AuthTest do
  use Jiyi.DataCase

  alias Jiyi.Auth
  alias Jiyi.Schemas.AgentKey

  test "shared token allows any agent_id" do
    shared = Application.fetch_env!(:jiyi, :api_token)

    assert {:ok, %{agent_id: "any-agent"}} =
             Auth.authenticate(shared, %{agent_id: "any-agent", task: "t"})
  end

  test "per-agent key binds to declared agent_id" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    token = "key-#{System.unique_integer([:positive])}"
    insert_agent_key(token, agent_id)

    assert {:ok, %{agent_id: ^agent_id}} =
             Auth.authenticate(token, %{agent_id: agent_id, task: "t"})
  end

  test "per-agent key rejects mismatched agent_id" do
    token = "key-#{System.unique_integer([:positive])}"
    insert_agent_key(token, "agent-a")

    assert {:error, :agent_id_mismatch} =
             Auth.authenticate(token, %{agent_id: "agent-b", task: "t"})
  end

  test "per-agent key injects org_id when absent" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    org_id = "org-#{System.unique_integer([:positive])}"
    token = "key-#{System.unique_integer([:positive])}"
    insert_agent_key(token, agent_id, org_id)

    assert {:ok, %{agent_id: ^agent_id, org_id: ^org_id}} =
             Auth.authenticate(token, %{agent_id: agent_id, task: "t"})
  end

  test "per-agent key does not override request org_id" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    token = "key-#{System.unique_integer([:positive])}"
    insert_agent_key(token, agent_id, "key-org")

    assert {:ok, %{agent_id: ^agent_id, org_id: "request-org"}} =
             Auth.authenticate(token, %{agent_id: agent_id, org_id: "request-org", task: "t"})
  end

  test "invalid token is rejected" do
    assert {:error, :invalid_token} = Auth.authenticate("not-a-real-key", %{agent_id: "a"})
  end

  test "missing token is rejected" do
    assert {:error, :missing_token} = Auth.authenticate(nil, %{agent_id: "a"})
    assert {:error, :missing_token} = Auth.authenticate("", %{agent_id: "a"})
  end

  test "mcp session token authenticates matching agent_id" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    {:ok, token} = Auth.issue_mcp_token(agent_id)

    assert {:ok, %{agent_id: ^agent_id}} =
             Auth.authenticate_mcp(token, %{agent_id: agent_id, task: "t"})
  end

  test "mcp session token rejects mismatched agent_id" do
    {:ok, token} = Auth.issue_mcp_token("agent-a")

    assert {:error, :agent_id_mismatch} =
             Auth.authenticate_mcp(token, %{agent_id: "agent-b", task: "t"})
  end

  test "expired mcp session token is rejected" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    token = insert_expired_mcp_token(agent_id)

    assert {:error, :expired_token} =
             Auth.authenticate_mcp(token, %{agent_id: agent_id, task: "t"})
  end

  test "mcp session token injects org_id" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    org_id = "org-#{System.unique_integer([:positive])}"
    {:ok, token} = Auth.issue_mcp_token(agent_id, org_id)

    assert {:ok, %{agent_id: ^agent_id, org_id: ^org_id}} =
             Auth.authenticate_mcp(token, %{agent_id: agent_id, task: "t"})
  end

  test "shared token preserves claimed human_asserted trust tier" do
    shared = Application.fetch_env!(:jiyi, :api_token)

    assert {:ok, %{provenance: %{"trust_tier" => "human_asserted"}}} =
             Auth.authenticate(shared, %{
               agent_id: "any-agent",
               provenance: %{"trust_tier" => "human_asserted"},
               task: "t"
             })
  end

  test "per-agent key clamps human_asserted claim to agent_derived" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    token = "key-#{System.unique_integer([:positive])}"
    insert_agent_key(token, agent_id)

    assert {:ok, %{provenance: %{"trust_tier" => "agent_derived"}}} =
             Auth.authenticate(token, %{
               agent_id: agent_id,
               provenance: %{"trust_tier" => "human_asserted"},
               task: "t"
             })
  end

  test "per-agent key allows agent_derived claim unchanged" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    token = "key-#{System.unique_integer([:positive])}"
    insert_agent_key(token, agent_id)

    assert {:ok, %{provenance: %{"trust_tier" => "agent_derived"}}} =
             Auth.authenticate(token, %{
               agent_id: agent_id,
               provenance: %{"trust_tier" => "agent_derived"},
               task: "t"
             })
  end

  test "mcp session token clamps human_asserted claim" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    {:ok, token} = Auth.issue_mcp_token(agent_id)

    assert {:ok, %{provenance: %{"trust_tier" => "agent_derived"}}} =
             Auth.authenticate_mcp(token, %{
               agent_id: agent_id,
               provenance: %{"trust_tier" => "human_asserted"},
               task: "t"
             })
  end

  defp insert_expired_mcp_token(agent_id) do
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

    token
  end

  defp insert_agent_key(token, agent_id, org_id \\ nil) do
    hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    %AgentKey{}
    |> AgentKey.changeset(%{
      key_hash: hash,
      agent_id: agent_id,
      org_id: org_id,
      inserted_at: DateTime.utc_now()
    })
    |> Jiyi.Repo.insert!()
  end
end
