defmodule Jiyi.Memory.SessionMonitorTest do
  use Jiyi.DataCase

  alias Jiyi.Memory.SessionSupervisor

  setup do
    handler_id = "test-session-crash-handler-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [[:jiyi, :session, :crash], [:jiyi, :session, :restart]],
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "emits crash telemetry on every SessionState crash" do
    session_id = "session-#{System.unique_integer([:positive])}"
    {:ok, _} = SessionSupervisor.start_session(session_id)

    [{state_pid, _}] = Registry.lookup(Jiyi.Registry, {Jiyi.Memory.SessionState, session_id})
    Process.exit(state_pid, :kill)

    assert_receive {:telemetry, [:jiyi, :session, :crash], %{count: 1},
                    %{session_id: ^session_id}}

    new_pid = wait_for_session_restart(session_id, state_pid)
    assert new_pid != state_pid

    Process.sleep(200)
    Process.exit(new_pid, :kill)

    assert_receive {:telemetry, [:jiyi, :session, :crash], %{count: 1},
                    %{session_id: ^session_id}},
                   2000
  end

  defp wait_for_session_restart(session_id, old_pid, attempts \\ 50) do
    case Registry.lookup(Jiyi.Registry, {Jiyi.Memory.SessionState, session_id}) do
      [{pid, _}] when pid != old_pid ->
        pid

      _ when attempts > 0 ->
        Process.sleep(20)
        wait_for_session_restart(session_id, old_pid, attempts - 1)

      _ ->
        nil
    end
  end
end
