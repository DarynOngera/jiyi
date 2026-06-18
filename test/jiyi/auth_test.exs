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
