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

  def hold_and_delete(target_table, payload, reason, struct_to_delete) do
    GenServer.call(
      __MODULE__,
      {:hold_and_delete, target_table, payload, reason, struct_to_delete}
    )
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
    entry = insert_entry(target_table, payload, reason)

    :telemetry.execute([:jiyi, :memory, :quarantined], %{count: 1}, %{
      target_table: target_table,
      id: entry.id
    })

    {:reply, {:ok, entry.id}, state}
  end

  def handle_call(
        {:hold_and_delete, target_table, payload, reason, struct_to_delete},
        _from,
        state
      ) do
    result =
      Repo.transaction(fn ->
        entry = insert_entry(target_table, payload, reason)

        case Repo.delete(struct_to_delete, stale_error_field: :id) do
          {:ok, _} ->
            :telemetry.execute([:jiyi, :memory, :quarantined], %{count: 1}, %{
              target_table: target_table,
              id: entry.id
            })

            entry.id

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    {:reply, result, state}
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
        end

        payload = map_keys_to_atoms(entry.payload)
        content_hash = Map.get(payload, :content_hash)
        acquire_content_hash_lock(content_hash)

        store_result =
          case entry.target_table do
            "episodic_events" ->
              Jiyi.Memory.EpisodicStore.write_logic(payload, bypass_quarantine: true)

            "semantic_facts" ->
              Jiyi.Memory.SemanticStore.write_logic(payload, bypass_quarantine: true)

            _ ->
              Repo.rollback(:unknown_target)
          end

        case store_result do
          {:ok, _} ->
            entry
            |> QuarantineEntry.changeset(%{status: "promoted", reviewed_at: now})
            |> Repo.update!()

            store_result

          {:duplicate, _} ->
            entry
            |> QuarantineEntry.changeset(%{status: "promoted", reviewed_at: now})
            |> Repo.update!()

            store_result

          error ->
            Repo.rollback(error)
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
          if entry.status != "pending" do
            {:error, :already_reviewed}
          else
            entry
            |> QuarantineEntry.changeset(%{status: "rejected", reviewed_at: now})
            |> Repo.update()
            |> case do
              {:ok, _} -> :ok
              {:error, changeset} -> {:error, changeset}
            end
          end
      end

    {:reply, result, state}
  end

  defp insert_entry(target_table, payload, reason) do
    %QuarantineEntry{}
    |> QuarantineEntry.changeset(%{
      target_table: target_table,
      payload: payload,
      reason: reason,
      status: "pending",
      created_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp map_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), map_keys_to_atoms(v)} end)
  rescue
    ArgumentError -> Map.new(map, fn {k, v} -> {String.to_atom(k), map_keys_to_atoms(v)} end)
  end

  defp map_keys_to_atoms(value), do: value

  defp acquire_content_hash_lock(nil), do: :ok

  defp acquire_content_hash_lock(content_hash) do
    lock_id = :erlang.phash2(content_hash)
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_id])
    :ok
  end
end
