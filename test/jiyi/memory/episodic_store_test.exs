defmodule Jiyi.Memory.EpisodicStoreTest do
  use Jiyi.DataCase

  alias Jiyi.Memory.EpisodicStore

  describe "write/1" do
    test "deduplicates within the content_hash window" do
      attrs = base_attrs("User reported phishing email")

      assert {:ok, %{id: id}} = EpisodicStore.write(attrs)
      assert {:duplicate, ^id} = EpisodicStore.write(attrs)
    end

    test "routes external_untrusted writes to quarantine" do
      attrs =
        base_attrs("Suspicious IOC from feed")
        |> Map.put(:trust_tier, "external_untrusted")

      assert {:quarantined, _id} = EpisodicStore.write(attrs)
    end

    test "writes human_asserted directly to the table" do
      attrs =
        base_attrs("Confirmed malicious domain")
        |> Map.put(:trust_tier, "human_asserted")

      assert {:ok, _id} = EpisodicStore.write(attrs)
    end
  end

  defp base_attrs(summary) do
    %{
      agent_id: "agent-1",
      session_id: "session-1",
      summary: summary,
      provenance_source: "user_message",
      ingestion_method: "direct_write",
      trust_tier: "agent_derived",
      scope: "agent_private"
    }
  end
end
