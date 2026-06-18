defmodule Jiyi.Memory.QuarantineTest do
  use Jiyi.DataCase

  alias Jiyi.Memory.Quarantine
  alias Jiyi.Schemas.{EpisodicEvent, QuarantineEntry}

  test "promote moves quarantined episodic event to the table" do
    attrs = %{
      agent_id: "agent-1",
      session_id: "session-1",
      summary: "Suspicious IOC from feed",
      provenance_source: "feed",
      ingestion_method: "api",
      trust_tier: "external_untrusted",
      scope: "agent_private"
    }

    {:quarantined, id} = Jiyi.Memory.EpisodicStore.write(attrs)

    assert {:ok, _event_id} = Quarantine.promote(id)

    entry = Jiyi.Repo.get!(QuarantineEntry, id)
    assert entry.status == "promoted"

    assert Jiyi.Repo.get_by(EpisodicEvent, content_hash: entry.payload["content_hash"])
  end

  test "promote reverts to pending when store write fails" do
    payload = %{
      "subject" => "user",
      "predicate" => "reported",
      "object" => "phishing",
      "provenance_source" => "feed",
      "ingestion_method" => "api",
      "trust_tier" => "external_untrusted",
      "scope" => "agent_private"
    }

    {:ok, id} = Quarantine.hold("semantic_facts", payload, "test: missing agent_id")

    assert {:error, _changeset} = Quarantine.promote(id)

    entry = Jiyi.Repo.get!(QuarantineEntry, id)
    assert entry.status == "pending"
    assert is_nil(entry.reviewed_at)
  end
end
