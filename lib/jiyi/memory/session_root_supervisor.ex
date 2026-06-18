defmodule Jiyi.Memory.SessionRootSupervisor do
  @moduledoc """
  Per-session supervisor that isolates restart intensity to one session.
  """

  use Supervisor

  def start_link(session_id) do
    Supervisor.start_link(__MODULE__, session_id, name: via(session_id))
  end

  @impl true
  def init(session_id) do
    children = [
      {Jiyi.Memory.SessionState, session_id},
      {Jiyi.Memory.SessionMonitor, session_id}
    ]

    Supervisor.init(children,
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end

  def via(session_id) do
    {:via, Registry, {Jiyi.Registry, {__MODULE__, session_id}}}
  end
end
