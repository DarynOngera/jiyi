defmodule Jiyi.Memory.SessionStateTest do
  use Jiyi.DataCase

  alias Jiyi.Memory.{SessionState, SessionSupervisor}

  describe "session lifecycle" do
    test "rehydrates working memory after a crash" do
      session_id = "session-#{System.unique_integer([:positive])}"

      {:ok, _pid} = SessionSupervisor.start_session(session_id)
      :ok = SessionState.put(session_id, :active_task, "review_alert")
      :ok = SessionState.checkpoint(session_id)

      [{old_pid, _}] = Registry.lookup(Jiyi.Registry, {SessionState, session_id})
      Process.exit(old_pid, :kill)

      :ok =
        wait_for(fn ->
          case Registry.lookup(Jiyi.Registry, {SessionState, session_id}) do
            [{pid, _}] -> pid != old_pid
            [] -> false
          end
        end)

      assert SessionState.get(session_id, :active_task) == "review_alert"
    end
  end

  defp wait_for(fun, attempts \\ 50) do
    if fun.() do
      :ok
    else
      if attempts > 0 do
        Process.sleep(20)
        wait_for(fun, attempts - 1)
      else
        :timeout
      end
    end
  end
end
