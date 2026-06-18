defmodule Jiyi.Memory.SessionMonitor do
  @moduledoc """
  Monitors a SessionState process and emits telemetry when it crashes.

  After a crash the monitor re-attaches to the restarted SessionState so that
  every crash in a session is recorded, not just the first.
  """

  use GenServer

  @retry_interval_ms 100

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id)
  end

  def child_spec(init_arg) do
    %{
      id: {__MODULE__, init_arg},
      start: {__MODULE__, :start_link, [init_arg]},
      restart: :temporary
    }
  end

  @impl true
  def init(session_id) do
    Process.set_label({__MODULE__, session_id})
    state = %{session_id: session_id}

    case monitor_session(session_id) do
      :ok -> {:ok, state}
      :not_found -> schedule_retry(state)
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    if crash_reason?(reason) do
      :telemetry.execute([:jiyi, :session, :crash], %{count: 1}, %{
        session_id: state.session_id,
        reason: reason
      })

      schedule_retry(state)
    else
      {:stop, :normal, state}
    end
  end

  def handle_info(:retry_monitor, state) do
    case monitor_session(state.session_id) do
      :ok -> {:noreply, state}
      :not_found -> schedule_retry(state)
    end
  end

  defp monitor_session(session_id) do
    case Registry.lookup(Jiyi.Registry, {Jiyi.Memory.SessionState, session_id}) do
      [{pid, _}] ->
        Process.monitor(pid)
        :ok

      [] ->
        :not_found
    end
  end

  defp schedule_retry(state) do
    Process.send_after(self(), :retry_monitor, @retry_interval_ms)
    {:noreply, state}
  end

  defp crash_reason?(reason) do
    reason not in [:normal, :shutdown] and not is_tuple(reason)
  end
end
