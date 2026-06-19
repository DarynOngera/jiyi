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

  def write(attrs, opts \\ []) do
    GenServer.call(__MODULE__, {:write, attrs, opts})
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
  def handle_call({:write, attrs, opts}, _from, state) do
    result = write_logic(attrs, opts)
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

  def write_logic(attrs, opts \\ []) do
    now = DateTime.utc_now()

    content = normalize_content(attrs)
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    attrs =
      Map.merge(attrs, %{
        content_hash: content_hash,
        learned_at: Map.get(attrs, :learned_at, now),
        valid_from: Map.get(attrs, :valid_from, now)
      })

    if quarantine?(attrs) and not Keyword.get(opts, :bypass_quarantine, false) do
      {:ok, id} = Jiyi.Memory.Quarantine.hold("semantic_facts", attrs, "external_untrusted")
      :telemetry.execute([:jiyi, :memory, :quarantined], %{count: 1}, %{store: :semantic})
      {:quarantined, id}
    else
      changeset = SemanticFact.changeset(%SemanticFact{}, attrs)

      window = Application.fetch_env!(:jiyi, :dedup_window_seconds)
      window_start = DateTime.add(now, -window, :second)

      case recent_duplicate(content_hash, window_start) do
        nil ->
          case Repo.insert(changeset) do
            {:ok, fact} ->
              :telemetry.execute([:jiyi, :memory, :write], %{count: 1}, %{
                store: :semantic,
                id: fact.id
              })

              {:ok, fact.id}

            {:error, _} ->
              case recent_duplicate(content_hash, window_start) do
                nil -> {:error, :insert_failed}
                fact -> {:duplicate, fact.id}
              end
          end

        fact ->
          :telemetry.execute([:jiyi, :memory, :duplicate], %{count: 1}, %{
            store: :semantic,
            id: fact.id
          })

          {:duplicate, fact.id}
      end
    end
  end

  defp do_query(filters, opts) do
    limit = Keyword.get(opts, :limit, 10)

    SemanticFact
    |> filter_query(filters)
    |> select_relevance(filters)
    |> where([f], is_nil(f.valid_until))
    |> limit(^limit)
    |> Repo.all()
    |> tap(fn _ ->
      :telemetry.execute([:jiyi, :memory, :read], %{count: 1}, %{store: :semantic})
    end)
  end

  defp select_relevance(query, filters) do
    case Keyword.get(filters, :text) do
      nil ->
        query

      value ->
        select_merge(query, [f], %{
          relevance:
            fragment(
              "ts_rank(to_tsvector('english', ? || ' ' || ? || ' ' || ?), plainto_tsquery('english', ?))",
              f.subject,
              f.predicate,
              f.object,
              ^value
            )
        })
    end
  end

  defp filter_query(query, filters) do
    Enum.reduce(filters, query, fn
      {:subject, value}, q ->
        where(q, [f], f.subject == ^value)

      {:predicate, value}, q ->
        where(q, [f], f.predicate == ^value)

      {:object, value}, q ->
        where(q, [f], f.object == ^value)

      {:scope, scopes}, q ->
        scope_filter(q, scopes)

      {:text, value}, q ->
        q
        |> where(
          [f],
          fragment(
            "to_tsvector('english', ? || ' ' || ? || ' ' || ?) @@ plainto_tsquery('english', ?)",
            f.subject,
            f.predicate,
            f.object,
            ^value
          )
        )
        |> order_by([f],
          desc:
            fragment(
              "ts_rank(to_tsvector('english', ? || ' ' || ? || ' ' || ?), plainto_tsquery('english', ?))",
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

  defp scope_filter(query, %{agent_id: agent_id, scopes: scopes} = ctx) do
    session_id = Map.get(ctx, :session_id)
    org_id = Map.get(ctx, :org_id)

    condition =
      Enum.reduce(scopes, false, fn scope, dynamic ->
        case scope do
          "agent_private" ->
            dynamic([f], ^dynamic or (f.scope == "agent_private" and f.agent_id == ^agent_id))

          "session_shared" when is_binary(session_id) and session_id != "" ->
            dynamic(
              [f],
              ^dynamic or (f.scope == "session_shared" and f.session_id == ^session_id)
            )

          "org_shared" when is_binary(org_id) and org_id != "" ->
            dynamic([f], ^dynamic or (f.scope == "org_shared" and f.org_id == ^org_id))

          _ ->
            dynamic
        end
      end)

    where(query, ^condition)
  end

  defp recent_duplicate(content_hash, window_start) do
    Repo.one(
      from(f in SemanticFact,
        where:
          f.content_hash == ^content_hash and f.learned_at > ^window_start and
            is_nil(f.valid_until)
      )
    )
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

  defp anomaly?(attrs) do
    text =
      "#{Map.get(attrs, :subject, "")} #{Map.get(attrs, :predicate, "")} #{Map.get(attrs, :object, "")}"

    Jiyi.Anomaly.Detector.anomalous?(text)
  end
end
