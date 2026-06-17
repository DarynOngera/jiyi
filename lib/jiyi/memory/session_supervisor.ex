defmodule Jiyi.Memory.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for per-session SessionState processes.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end

  def start_session(session_id) when is_binary(session_id) do
    spec = %{
      id: {Jiyi.Memory.SessionState, session_id},
      start: {Jiyi.Memory.SessionState, :start_link, [session_id]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def via(session_id) do
    {:via, Registry, {Jiyi.Registry, {Jiyi.Memory.SessionState, session_id}}}
  end
end
