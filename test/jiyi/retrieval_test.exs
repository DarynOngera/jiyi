defmodule Jiyi.RetrievalTest do
  use ExUnit.Case

  alias Jiyi.Retrieval

  setup do
    start_supervised!(Jiyi.Retrieval.Supervisor)
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
  end
end
