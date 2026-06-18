defmodule Jiyi.RetrievalIntegrationTest do
  use Jiyi.DataCase

  alias Jiyi.Retrieval
  alias Jiyi.Memory.{EpisodicStore, SemanticStore}

  test "assembles context from episodic and semantic stores" do
    agent_id = "agent-#{System.unique_integer([:positive])}"
    session_id = "session-#{System.unique_integer([:positive])}"

    {:ok, _episodic_id} =
      EpisodicStore.write(%{
        agent_id: agent_id,
        session_id: session_id,
        summary: "User reported phishing email",
        provenance_source: "user_message",
        ingestion_method: "direct_write",
        trust_tier: "human_asserted",
        scope: "agent_private"
      })

    {:ok, _semantic_id} =
      SemanticStore.write(%{
        subject: "user",
        predicate: "reported",
        object: "phishing email",
        agent_id: agent_id,
        provenance_source: "user_message",
        ingestion_method: "direct_write",
        trust_tier: "agent_derived",
        scope: "agent_private"
      })

    result =
      Retrieval.assemble(%{
        agent_id: agent_id,
        session_id: session_id,
        task: "phishing email"
      })

    assert result.token_count > 0
    assert result.assembled_context =~ "phishing email"
    assert Enum.any?(result.sources, &(&1.type == "episodic"))
    assert Enum.any?(result.sources, &(&1.type == "semantic"))
  end
end
