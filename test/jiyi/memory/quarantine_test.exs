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

  test "hold_and_delete atomically quarantines and removes the record" do
    now = DateTime.utc_now()

    event =
      %EpisodicEvent{}
      |> EpisodicEvent.changeset(%{
        agent_id: "agent-1",
        session_id: "session-1",
        summary: "Suspicious IOC from feed",
        occurred_at: now,
        provenance_source: "feed",
        ingestion_method: "api",
        trust_tier: "agent_derived",
        scope: "agent_private",
        content_hash: :crypto.hash(:sha256, "x") |> Base.encode16(case: :lower)
      })
      |> Jiyi.Repo.insert!()

    payload = event |> Map.from_struct() |> Map.drop([:__meta__])

    assert {:ok, _id} = Quarantine.hold_and_delete("episodic_events", payload, "test", event)

    assert is_nil(Jiyi.Repo.get(EpisodicEvent, event.id))
    assert Jiyi.Repo.get_by(QuarantineEntry, reason: "test", target_table: "episodic_events")
  end

  test "hold_and_delete rolls back quarantine insert when delete fails" do
    payload = %{
      "agent_id" => "agent-1",
      "session_id" => "session-1",
      "summary" => "Suspicious IOC from feed",
      "occurred_at" => DateTime.utc_now(),
      "provenance_source" => "feed",
      "ingestion_method" => "api",
      "trust_tier" => "agent_derived",
      "scope" => "agent_private",
      "content_hash" => :crypto.hash(:sha256, "x") |> Base.encode16(case: :lower)
    }

    fake_event = %EpisodicEvent{id: Ecto.UUID.generate()}

    assert {:error, _changeset} =
             Quarantine.hold_and_delete("episodic_events", payload, "test", fake_event)

    refute Jiyi.Repo.get_by(QuarantineEntry, reason: "test")
  end
end
