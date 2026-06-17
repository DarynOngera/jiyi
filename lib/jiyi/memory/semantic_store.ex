defmodule Jiyi.Memory.SemanticStore do
  @moduledoc """
  GenServer fronting Ecto for semantic fact writes, queries, and invalidation.
  """

  use GenServer

  import Ecto.Query

  alias Jiyi.Repo
  alias Jiyi.Schemas.SemanticFact

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def write(attrs) do
    GenServer.call(__MODULE__, {:write, attrs})
  end

  def query(filters, opts \\ []) do
    GenServer.call(__MODULE__, {:query, filters, opts})
  end

  def invalidate(fact_id, at \\ DateTime.utc_now()) do
    GenServer.call(__MODULE__, {:invalidate, fact_id, at})
  end

  @impl true
  def init(_init_arg) do
    Process.set_label(__MODULE__)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:write, attrs}, _from, state) do
    result = do_write(attrs)
    {:reply, result, state}
  end

  def handle_call({:query, filters, opts}, _from, state) do
    facts = do_query(filters, opts)
    {:reply, facts, state}
  end

  def handle_call({:invalidate, fact_id, at}, _from, state) do
    result = do_invalidate(fact_id, at)
    {:reply, result, state}
  end

  defp do_write(attrs) do
    now = DateTime.utc_now()

    content = normalize_content(attrs)
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    attrs =
      Map.merge(attrs, %{
        content_hash: content_hash,
        learned_at: Map.get(attrs, :learned_at, now),
        valid_from: Map.get(attrs, :valid_from, now)
      })

    if quarantine?(attrs) do
      {:ok, id} = Jiyi.Memory.Quarantine.hold("semantic_facts", attrs, "external_untrusted")
      :telemetry.execute([:jiyi, :memory, :quarantined], %{count: 1}, %{store: :semantic})
      {:quarantined, id}
    else
      changeset = SemanticFact.changeset(%SemanticFact{}, attrs)

      case Repo.get_by(SemanticFact, content_hash: content_hash) do
        nil ->
          case Repo.insert(changeset) do
            {:ok, fact} ->
              :telemetry.execute([:jiyi, :memory, :write], %{count: 1}, %{
                store: :semantic,
                id: fact.id
              })

              {:ok, fact.id}

            {:error, _} ->
              case Repo.get_by(SemanticFact, content_hash: content_hash) do
                nil -> {:error, :insert_failed}
                fact -> {:duplicate, fact.id}
              end
          end

        fact ->
          {:duplicate, fact.id}
      end
    end
  end

  defp do_query(filters, opts) do
    limit = Keyword.get(opts, :limit, 10)

    SemanticFact
    |> filter_query(filters)
    |> where([f], is_nil(f.valid_until))
    |> limit(^limit)
    |> Repo.all()
  end

  defp filter_query(query, filters) do
    Enum.reduce(filters, query, fn
      {:subject, value}, q ->
        where(q, [f], f.subject == ^value)

      {:predicate, value}, q ->
        where(q, [f], f.predicate == ^value)

      {:object, value}, q ->
        where(q, [f], f.object == ^value)

      {:text, value}, q ->
        where(
          q,
          [f],
          fragment(
            "to_tsvector('english', ? || ' ' || ? || ' ' || ?) @@ plainto_tsquery('english', ?)",
            f.subject,
            f.predicate,
            f.object,
            ^value
          )
        )

      {:embedding, value}, q ->
        order_by(q, [f], fragment("? <-> ?", f.embedding, ^Pgvector.new(value)))

      _, q ->
        q
    end)
  end

  defp do_invalidate(fact_id, at) do
    case Repo.get(SemanticFact, fact_id) do
      nil ->
        {:error, :not_found}

      fact ->
        fact
        |> SemanticFact.changeset(%{valid_until: at})
        |> Repo.update()
        |> case do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp normalize_content(%{subject: s, predicate: p, object: o}) do
    [s, p, o]
    |> Enum.map(&String.downcase(String.trim(&1)))
    |> Enum.join("|")
  end

  defp normalize_content(_), do: ""

  defp quarantine?(attrs) do
    Map.get(attrs, :trust_tier) == "external_untrusted" or anomaly?(attrs)
  end

  defp anomaly?(_attrs), do: false
end
