defmodule Jiyi.Anomaly.Watcher do
  @moduledoc """
  Scheduled GenServer that scans recent memory writes for anomalies
  and routes hits into Quarantine.
  """

  use GenServer

  alias Jiyi.Repo
  alias Jiyi.Schemas.{EpisodicEvent, SemanticFact}

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def scan do
    GenServer.call(__MODULE__, :scan)
  end

  @impl true
  def init(_init_arg) do
    Process.set_label(__MODULE__)
    schedule_scan()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:scan, state) do
    do_scan()
    schedule_scan()
    {:noreply, state}
  end

  @impl true
  def handle_call(:scan, _from, state) do
    result = do_scan()
    {:reply, result, state}
  end

  defp do_scan do
    import Ecto.Query

    window = DateTime.add(DateTime.utc_now(), -300, :second)

    episodic =
      EpisodicEvent
      |> where([e], e.occurred_at > ^window)
      |> Repo.all()

    facts =
      SemanticFact
      |> where([f], f.learned_at > ^window)
      |> Repo.all()

    flagged =
      Enum.filter(episodic, &anomalous?/1) ++
        Enum.filter(facts, &anomalous?/1)

    Enum.each(flagged, fn record ->
      table = if is_struct(record, EpisodicEvent), do: "episodic_events", else: "semantic_facts"
      payload = serialize(record)
      Jiyi.Memory.Quarantine.hold(table, payload, "anomaly_watcher: instruction-like phrasing")
    end)

    {:ok, length(flagged)}
  end

  defp schedule_scan do
    :timer.send_interval(60_000, self(), :scan)
  end

  defp anomalous?(%EpisodicEvent{summary: summary}), do: instruction_like?(summary)

  defp anomalous?(%SemanticFact{subject: s, predicate: p, object: o}),
    do: instruction_like?(s <> " " <> p <> " " <> o)

  defp instruction_like?(text) when is_binary(text) do
    lower = String.downcase(text)

    patterns = [
      "ignore previous",
      "disregard",
      "forget",
      "you must",
      "do not mention",
      "do not reveal",
      "system prompt",
      "ignore the above"
    ]

    Enum.any?(patterns, &String.contains?(lower, &1))
  end

  defp instruction_like?(_), do: false

  defp serialize(%EpisodicEvent{} = event) do
    Map.from_struct(event)
    |> Map.drop([:__meta__])
  end

  defp serialize(%SemanticFact{} = fact) do
    Map.from_struct(fact)
    |> Map.drop([:__meta__])
  end
end
