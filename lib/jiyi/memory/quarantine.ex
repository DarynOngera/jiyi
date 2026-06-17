defmodule Jiyi.Memory.Quarantine do
  @moduledoc """
  Isolated hold buffer for untrusted or anomalous memory writes.
  """

  use GenServer

  import Ecto.Query

  alias Jiyi.Repo
  alias Jiyi.Schemas.QuarantineEntry

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def hold(target_table, payload, reason) do
    GenServer.call(__MODULE__, {:hold, target_table, payload, reason})
  end

  def list_pending do
    GenServer.call(__MODULE__, :list_pending)
  end

  def promote(id) do
    GenServer.call(__MODULE__, {:promote, id})
  end

  def reject(id) do
    GenServer.call(__MODULE__, {:reject, id})
  end

  @impl true
  def init(_init_arg) do
    Process.set_label(__MODULE__)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:hold, target_table, payload, reason}, _from, state) do
    entry =
      %QuarantineEntry{}
      |> QuarantineEntry.changeset(%{
        target_table: target_table,
        payload: payload,
        reason: reason,
        status: "pending",
        created_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    :telemetry.execute([:jiyi, :memory, :quarantined], %{count: 1}, %{
      target_table: target_table,
      id: entry.id
    })

    {:reply, {:ok, entry.id}, state}
  end

  def handle_call(:list_pending, _from, state) do
    entries =
      QuarantineEntry
      |> where([q], q.status == "pending")
      |> order_by([q], desc: q.created_at)
      |> Repo.all()

    {:reply, entries, state}
  end

  def handle_call({:promote, id}, _from, state) do
    now = DateTime.utc_now()

    result =
      Repo.transaction(fn ->
        entry = Repo.get!(QuarantineEntry, id)

        if entry.status != "pending" do
          Repo.rollback(:already_reviewed)
        else
          payload = map_keys_to_atoms(entry.payload)

          store_result =
            case entry.target_table do
              "episodic_events" -> Jiyi.Memory.EpisodicStore.write(payload)
              "semantic_facts" -> Jiyi.Memory.SemanticStore.write(payload)
              _ -> Repo.rollback(:unknown_target)
            end

          entry
          |> QuarantineEntry.changeset(%{status: "promoted", reviewed_at: now})
          |> Repo.update!()

          store_result
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:reject, id}, _from, state) do
    now = DateTime.utc_now()

    result =
      case Repo.get(QuarantineEntry, id) do
        nil ->
          {:error, :not_found}

        entry ->
          entry
          |> QuarantineEntry.changeset(%{status: "rejected", reviewed_at: now})
          |> Repo.update()
          |> case do
            {:ok, _} -> :ok
            {:error, changeset} -> {:error, changeset}
          end
      end

    {:reply, result, state}
  end

  defp map_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), map_keys_to_atoms(v)} end)
  rescue
    ArgumentError -> Map.new(map, fn {k, v} -> {String.to_atom(k), map_keys_to_atoms(v)} end)
  end

  defp map_keys_to_atoms(value), do: value
end
