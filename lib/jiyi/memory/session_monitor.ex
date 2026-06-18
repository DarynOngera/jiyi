defmodule Jiyi.Memory.SessionMonitor do
  @moduledoc """
  Monitors a SessionState process and emits telemetry when it crashes.
  """

  use GenServer

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

    case Registry.lookup(Jiyi.Registry, {Jiyi.Memory.SessionState, session_id}) do
      [{pid, _}] -> Process.monitor(pid)
      [] -> :ok
    end

    {:ok, %{session_id: session_id}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state)
      when reason not in [:normal, :shutdown] and not is_tuple(reason) do
    :telemetry.execute([:jiyi, :session, :crash], %{count: 1}, %{
      session_id: state.session_id,
      reason: reason
    })

    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:stop, :normal, state}
  end
end
