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
    result = do_write(attrs, opts)
    {:reply, result, state}
  end

  def handle_call({:query, filters, opts}, _from, state) do
    events = do_query(filters, opts)
    {:reply, events, state}
  end

  defp do_write(attrs, opts) do
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

      case Repo.get_by(EpisodicEvent, content_hash: content_hash) do
        nil ->
          case Repo.insert(changeset) do
            {:ok, event} ->
              :telemetry.execute([:jiyi, :memory, :write], %{count: 1}, %{
                store: :episodic,
                id: event.id
              })

              {:ok, event.id}

            {:error, _} ->
              case Repo.get_by(EpisodicEvent, content_hash: content_hash) do
                nil -> {:error, :insert_failed}
                event -> {:duplicate, event.id}
              end
          end

        event ->
          {:duplicate, event.id}
      end
    end
  end

  defp do_query(filters, opts) do
    limit = Keyword.get(opts, :limit, 10)

    EpisodicEvent
    |> filter_query(filters)
    |> limit(^limit)
    |> Repo.all()
  end

  defp filter_query(query, filters) do
    Enum.reduce(filters, query, fn
      {:agent_id, value}, q ->
        where(q, [e], e.agent_id == ^value)

      {:occurred_after, value}, q ->
        where(q, [e], e.occurred_at > ^value)

      {:text, value}, q ->
        where(
          q,
          [e],
          fragment(
            "to_tsvector('english', ?) @@ plainto_tsquery('english', ?)",
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

  defp normalize_content(%{summary: summary}), do: String.downcase(String.trim(summary))
  defp normalize_content(_), do: ""

  defp quarantine?(attrs) do
    Map.get(attrs, :trust_tier) == "external_untrusted" or anomaly?(attrs)
  end

  defp anomaly?(_attrs), do: false
end
