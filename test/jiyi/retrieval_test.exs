defmodule Jiyi.RetrievalTest do
  use ExUnit.Case

  alias Jiyi.Retrieval

  setup do
    if Process.whereis(Jiyi.Repo) do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Jiyi.Repo)
      Ecto.Adapters.SQL.Sandbox.mode(Jiyi.Repo, {:shared, self()})
    end

    unless Process.whereis(Jiyi.Retrieval.Supervisor) do
      start_supervised!(Jiyi.Retrieval.Supervisor)
    end

    unless Process.whereis(Jiyi.Anomaly.ReferenceStore) do
      start_supervised!(Jiyi.Anomaly.ReferenceStore)
    end

    :ok
  end

  describe "assemble/1" do
    test "returns a budgeted context map" do
      result =
        Retrieval.assemble(%{
          agent_id: "agent-1",
          session_id: "session-1",
          task: "investigate alert"
        })

      assert is_binary(result.assembled_context)
      assert is_list(result.sources)
      assert is_integer(result.token_count)
      assert result.token_count >= 0
    end

    test "includes procedural memory for matching tasks" do
      result =
        Retrieval.assemble(%{
          agent_id: "agent-1",
          session_id: "session-1",
          task: "investigate alert"
        })

      assert Enum.any?(result.sources, &(&1.type == "procedural"))
    end
  end
end
