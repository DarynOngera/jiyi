defmodule JiyiTest do
  use Jiyi.DataCase
  doctest Jiyi

  test "public API is loadable" do
    assert function_exported?(Jiyi, :write_memory, 1)
    assert function_exported?(Jiyi, :assemble_context, 1)
  end

  describe "write_memory/1 validation" do
    test "rejects unknown memory type" do
      assert {:error, :invalid_memory_type} =
               Jiyi.write_memory(%{
                 type: "procedural",
                 agent_id: "a",
                 content: %{"summary" => "x"},
                 provenance: %{
                   "source" => "s",
                   "ingestion_method" => "m",
                   "trust_tier" => "agent_derived"
                 },
                 scope: "agent_private"
               })
    end

    test "rejects invalid scope" do
      assert {:error, :invalid_scope} =
               Jiyi.write_memory(%{
                 type: "episodic",
                 agent_id: "a",
                 session_id: "s",
                 content: %{"summary" => "x"},
                 provenance: %{
                   "source" => "s",
                   "ingestion_method" => "m",
                   "trust_tier" => "agent_derived"
                 },
                 scope: "world_readable"
               })
    end

    test "rejects invalid trust tier" do
      assert {:error, :invalid_trust_tier} =
               Jiyi.write_memory(%{
                 type: "episodic",
                 agent_id: "a",
                 session_id: "s",
                 content: %{"summary" => "x"},
                 provenance: %{
                   "source" => "s",
                   "ingestion_method" => "m",
                   "trust_tier" => "trusted"
                 },
                 scope: "agent_private"
               })
    end

    test "rejects episodic content without summary" do
      assert {:error, :missing_summary} =
               Jiyi.write_memory(%{
                 type: "episodic",
                 agent_id: "a",
                 session_id: "s",
                 content: %{},
                 provenance: %{
                   "source" => "s",
                   "ingestion_method" => "m",
                   "trust_tier" => "agent_derived"
                 },
                 scope: "agent_private"
               })
    end

    test "rejects semantic content with missing fields" do
      assert {:error, :missing_semantic_fields} =
               Jiyi.write_memory(%{
                 type: "semantic",
                 agent_id: "a",
                 content: %{"subject" => "s", "predicate" => "p"},
                 provenance: %{
                   "source" => "s",
                   "ingestion_method" => "m",
                   "trust_tier" => "agent_derived"
                 },
                 scope: "agent_private"
               })
    end

    test "rejects session_shared semantic fact without session_id" do
      assert {:error, :missing_session_id} =
               Jiyi.write_memory(%{
                 type: "semantic",
                 agent_id: "a",
                 content: %{"subject" => "s", "predicate" => "p", "object" => "o"},
                 provenance: %{
                   "source" => "s",
                   "ingestion_method" => "m",
                   "trust_tier" => "agent_derived"
                 },
                 scope: "session_shared"
               })

      assert {:ok, _id} =
               Jiyi.write_memory(%{
                 type: "semantic",
                 agent_id: "a",
                 session_id: "s",
                 content: %{"subject" => "s", "predicate" => "p", "object" => "o"},
                 provenance: %{
                   "source" => "s",
                   "ingestion_method" => "m",
                   "trust_tier" => "agent_derived"
                 },
                 scope: "session_shared"
               })
    end
  end
end
