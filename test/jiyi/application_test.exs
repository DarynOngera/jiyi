defmodule Jiyi.ApplicationTest do
  use ExUnit.Case

  describe "supervision tree" do
    test "crashing a memory leaf process restarts only that subtree" do
      {:ok, _} = Application.ensure_all_started(:jiyi)

      assert Process.whereis(Jiyi.Memory.EpisodicStore)

      old_pid = Process.whereis(Jiyi.Memory.EpisodicStore)
      old_supervisor_pid = Process.whereis(Jiyi.Memory.Supervisor)
      old_retrieval_pid = Process.whereis(Jiyi.Retrieval.Supervisor)

      Process.exit(old_pid, :kill)

      # Wait for supervisor to restart the child.
      :ok = wait_for(fn -> Process.whereis(Jiyi.Memory.EpisodicStore) != old_pid end)

      new_pid = Process.whereis(Jiyi.Memory.EpisodicStore)
      assert new_pid != old_pid
      assert Process.alive?(new_pid)

      # Sibling supervisors should be unaffected.
      assert Process.whereis(Jiyi.Memory.Supervisor) == old_supervisor_pid
      assert Process.whereis(Jiyi.Retrieval.Supervisor) == old_retrieval_pid
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
