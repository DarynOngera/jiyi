defmodule Jiyi.Memory.SessionState do
  @moduledoc """
  Per-session working memory GenServer.
  """

  use GenServer

  alias Jiyi.Repo
  alias Jiyi.Schemas.SessionCheckpoint

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id,
      name: Jiyi.Memory.SessionSupervisor.via(session_id)
    )
  end

  def get(session_id, key) do
    GenServer.call(Jiyi.Memory.SessionSupervisor.via(session_id), {:get, key})
  end

  def put(session_id, key, value) do
    GenServer.call(Jiyi.Memory.SessionSupervisor.via(session_id), {:put, key, value})
  end

  def checkpoint(session_id) do
    GenServer.call(Jiyi.Memory.SessionSupervisor.via(session_id), :checkpoint)
  end

  @impl true
  def init(session_id) do
    Process.set_label({__MODULE__, session_id})

    state =
      case Repo.get(SessionCheckpoint, session_id) do
        nil ->
          %{session_id: session_id, data: %{}, dirty: false, writes: 0}

        checkpoint ->
          %{session_id: session_id, data: checkpoint.working_memory, dirty: false, writes: 0}
      end

    schedule_checkpoint(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state.data, to_string(key)), state}
  end

  def handle_call({:put, key, value}, _from, state) do
    new_data = Map.put(state.data, to_string(key), value)
    writes = state.writes + 1
    state = %{state | data: new_data, dirty: true, writes: writes}

    state = maybe_checkpoint(state)
    {:reply, :ok, state}
  end

  def handle_call(:checkpoint, _from, state) do
    state = flush(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:checkpoint, state) do
    state = flush(state)
    schedule_checkpoint(state)
    {:noreply, state}
  end

  defp maybe_checkpoint(state) do
    count_threshold = Application.fetch_env!(:jiyi, :session_checkpoint_write_count)

    if state.writes >= count_threshold do
      flush(state)
    else
      state
    end
  end

  defp flush(%{dirty: false} = state), do: state

  defp flush(state) do
    now = DateTime.utc_now()

    %SessionCheckpoint{}
    |> SessionCheckpoint.changeset(%{
      session_id: state.session_id,
      working_memory: state.data,
      updated_at: now
    })
    |> Repo.insert(
      on_conflict: {:replace, [:working_memory, :updated_at]},
      conflict_target: :session_id
    )

    %{state | dirty: false, writes: 0}
  end

  defp schedule_checkpoint(state) do
    interval = Application.fetch_env!(:jiyi, :session_checkpoint_interval_ms)
    Process.send_after(self(), :checkpoint, interval)
    state
  end
end
