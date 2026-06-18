defmodule Jiyi.Memory.EpisodicStore do
  @moduledoc """
  GenServer fronting Ecto for episodic event writes and queries.
  """

  use GenServer

  import Ecto.Query

  alias Jiyi.Repo
  alias Jiyi.Schemas.EpisodicEvent

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def write(attrs, opts \\ []) do
    GenServer.call(__MODULE__, {:write, attrs, opts})
  end

  def query(filters, opts \\ []) do
    GenServer.call(__MODULE__, {:query, filters, opts})
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
    events = do_query(filters, opts)
    {:reply, events, state}
  end

  def write_logic(attrs, opts \\ []) do
    now = DateTime.utc_now()

    content = normalize_content(attrs)
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    attrs =
      Map.merge(attrs, %{
        content_hash: content_hash,
        occurred_at: Map.get(attrs, :occurred_at, now)
      })

    if quarantine?(attrs) and not Keyword.get(opts, :bypass_quarantine, false) do
      {:ok, id} = Jiyi.Memory.Quarantine.hold("episodic_events", attrs, "external_untrusted")
      :telemetry.execute([:jiyi, :memory, :quarantined], %{count: 1}, %{store: :episodic})
      {:quarantined, id}
    else
      changeset = EpisodicEvent.changeset(%EpisodicEvent{}, attrs)

      window = Application.fetch_env!(:jiyi, :dedup_window_seconds)
      window_start = DateTime.add(now, -window, :second)

      case recent_duplicate(content_hash, window_start) do
        nil ->
          case Repo.insert(changeset) do
            {:ok, event} ->
              :telemetry.execute([:jiyi, :memory, :write], %{count: 1}, %{
                store: :episodic,
                id: event.id
              })

              {:ok, event.id}

            {:error, _} ->
              case recent_duplicate(content_hash, window_start) do
                nil -> {:error, :insert_failed}
                event -> {:duplicate, event.id}
              end
          end

        event ->
          :telemetry.execute([:jiyi, :memory, :duplicate], %{count: 1}, %{
            store: :episodic,
            id: event.id
          })

          {:duplicate, event.id}
      end
    end
  end

  defp do_query(filters, opts) do
    limit = Keyword.get(opts, :limit, 10)

    EpisodicEvent
    |> filter_query(filters)
    |> select_relevance(filters)
    |> limit(^limit)
    |> Repo.all()
    |> tap(fn _ ->
      :telemetry.execute([:jiyi, :memory, :read], %{count: 1}, %{store: :episodic})
    end)
  end

  defp select_relevance(query, filters) do
    case Keyword.get(filters, :text) do
      nil ->
        query

      value ->
        select_merge(query, [e], %{
          relevance:
            fragment(
              "ts_rank(to_tsvector('english', ?), plainto_tsquery('english', ?))",
              e.summary,
              ^value
            )
        })
    end
  end

  defp filter_query(query, filters) do
    Enum.reduce(filters, query, fn
      {:agent_id, value}, q ->
        where(q, [e], e.agent_id == ^value)

      {:scope, scopes}, q ->
        scope_filter(q, scopes)

      {:occurred_after, value}, q ->
        where(q, [e], e.occurred_at > ^value)

      {:text, value}, q ->
        q
        |> where(
          [e],
          fragment(
            "to_tsvector('english', ?) @@ plainto_tsquery('english', ?)",
            e.summary,
            ^value
          )
        )
        |> order_by([e],
          desc:
            fragment(
              "ts_rank(to_tsvector('english', ?), plainto_tsquery('english', ?))",
              e.summary,
              ^value
            )
        )

      {:embedding, value}, q ->
        order_by(q, [e], fragment("? <-> ?", e.embedding, ^Pgvector.new(value)))

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
            dynamic([e], ^dynamic or (e.scope == "agent_private" and e.agent_id == ^agent_id))

          "session_shared" when is_binary(session_id) and session_id != "" ->
            dynamic(
              [e],
              ^dynamic or (e.scope == "session_shared" and e.session_id == ^session_id)
            )

          "org_shared" when is_binary(org_id) and org_id != "" ->
            dynamic([e], ^dynamic or (e.scope == "org_shared" and e.org_id == ^org_id))

          _ ->
            dynamic
        end
      end)

    where(query, ^condition)
  end

  defp recent_duplicate(content_hash, window_start) do
    Repo.one(
      from(e in EpisodicEvent,
        where: e.content_hash == ^content_hash and e.occurred_at > ^window_start
      )
    )
  end

  defp normalize_content(%{summary: summary}), do: String.downcase(String.trim(summary))
  defp normalize_content(_), do: ""

  defp quarantine?(attrs) do
    Map.get(attrs, :trust_tier) == "external_untrusted" or anomaly?(attrs)
  end

  defp anomaly?(attrs) do
    summary = Map.get(attrs, :summary, "")
    Jiyi.Anomaly.Detector.instruction_like?(summary)
  end
end
