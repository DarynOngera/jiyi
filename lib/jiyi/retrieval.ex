defmodule Jiyi.Retrieval do
  @moduledoc """
  Plain-module retrieval pipeline: route -> fan-out -> rank -> compress -> format.
  """

  alias Jiyi.Memory.{EpisodicStore, Procedural, SemanticStore, SessionState}
  alias Jiyi.Schemas.{EpisodicEvent, SemanticFact}

  def assemble(request) do
    request = normalize_request(request)

    {episodic, semantic, working, procedural} = fan_out(request)

    ranked = rank(episodic ++ semantic ++ working ++ procedural, request)
    compressed = compress(ranked, request)

    emit_stage(:format, length(compressed))
    format(compressed, request)
  end

  defp normalize_request(request) do
    Map.merge(
      %{
        token_budget: 4000,
        memory_scopes: ["agent_private", "session_shared", "org_shared"]
      },
      request
    )
  end

  defp fan_out(%{task: task, agent_id: agent_id, memory_scopes: scopes} = request) do
    emit_stage(:fan_out, 0)

    scope_filter = %{
      agent_id: agent_id,
      scopes: scopes,
      session_id: Map.get(request, :session_id),
      org_id: Map.get(request, :org_id)
    }

    tasks = [
      Task.Supervisor.async(Jiyi.Retrieval.TaskSupervisor, fn ->
        {:episodic,
         safe_query(fn ->
           EpisodicStore.query([text: task, scope: scope_filter], limit: 10)
         end)}
      end),
      Task.Supervisor.async(Jiyi.Retrieval.TaskSupervisor, fn ->
        {:semantic,
         safe_query(fn ->
           SemanticStore.query([text: task, scope: scope_filter], limit: 10)
         end)}
      end),
      Task.Supervisor.async(Jiyi.Retrieval.TaskSupervisor, fn ->
        {:working, safe_query(fn -> fetch_working_memory(request) end)}
      end),
      Task.Supervisor.async(Jiyi.Retrieval.TaskSupervisor, fn ->
        {:procedural, safe_query(fn -> fetch_procedural(request) end)}
      end)
    ]

    results =
      tasks
      |> Task.yield_many(5_000)
      |> Enum.map(fn {task, result} ->
        case result do
          {:ok, value} ->
            value

          _ ->
            Task.shutdown(task, :brutal_kill)
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    episodic = Keyword.get(results, :episodic, [])
    semantic = Keyword.get(results, :semantic, [])
    working = Keyword.get(results, :working, [])
    procedural = Keyword.get(results, :procedural, [])

    {episodic, semantic, working, procedural}
  end

  defp safe_query(fun) do
    fun.()
  catch
    :exit, _ -> []
    _kind, _ -> []
  end

  defp fetch_working_memory(%{session_id: session_id}) when is_binary(session_id) do
    case Registry.lookup(Jiyi.Registry, {Jiyi.Memory.SessionState, session_id}) do
      [{_pid, _}] ->
        keys = [:active_task, :open_files, :recent_tool_outputs]

        Enum.map(keys, fn key ->
          case SessionState.get(session_id, key) do
            nil -> nil
            value -> %{type: :working, key: key, value: value}
          end
        end)
        |> Enum.reject(&is_nil/1)

      [] ->
        []
    end
  end

  defp fetch_working_memory(_), do: []

  defp fetch_procedural(%{task: task}) do
    task
    |> Procedural.content_for_task()
    |> Enum.with_index()
    |> Enum.map(fn {content, index} ->
      %{type: :procedural, content: content, id: "procedural-#{index}"}
    end)
  end

  defp rank(items, _request) do
    emit_stage(:rank, length(items))
    Enum.sort_by(items, &score/1, :desc)
  end

  defp score(item) do
    base_score(item) * recency_multiplier(item) * relevance_multiplier(item)
  end

  defp base_score(%EpisodicEvent{trust_tier: tier}), do: score_tier(tier)
  defp base_score(%SemanticFact{trust_tier: tier}), do: score_tier(tier)
  defp base_score(%{trust_tier: tier}), do: score_tier(tier)
  defp base_score(%{type: :working}), do: type_weight(:working)
  defp base_score(%{type: :procedural}), do: type_weight(:procedural)
  defp base_score(_), do: 0.5

  defp score_tier(tier), do: Map.get(trust_tier_weights(), tier, 0.5)

  defp trust_tier_weights do
    Application.get_env(:jiyi, :retrieval_trust_tier_weights, %{
      "human_asserted" => 1.0,
      "agent_derived" => 0.7,
      "external_untrusted" => 0.3
    })
  end

  defp type_weight(type) do
    Application.get_env(:jiyi, :retrieval_type_weights, %{
      working: 0.95,
      procedural: 0.85
    })
    |> Map.get(type, 0.85)
  end

  defp recency_multiplier(%{occurred_at: dt}), do: decay(dt)
  defp recency_multiplier(%{valid_from: dt}), do: decay(dt)
  defp recency_multiplier(_), do: 1.0

  defp decay(dt) do
    age_hours = max(0, DateTime.diff(DateTime.utc_now(), dt, :hour))
    half_life = Application.get_env(:jiyi, :retrieval_recency_half_life_hours, 1)
    floor = Application.get_env(:jiyi, :retrieval_min_recency_multiplier, 0.1)
    max(floor, :math.pow(0.5, age_hours / half_life))
  end

  defp relevance_multiplier(%{relevance: r}) when is_float(r) and r > 0, do: max(0.1, r)
  defp relevance_multiplier(_), do: 1.0

  defp compress(items, request) do
    emit_stage(:compress, length(items))
    budget = request.token_budget
    # Naive token estimation: 1 token ~= 4 chars of English text.
    char_budget = budget * 4

    {selected, _used} =
      Enum.reduce_while(items, {[], 0}, fn item, {acc, used} ->
        text = format_item(item)
        len = String.length(text)

        if used + len <= char_budget do
          {:cont, {[item | acc], used + len}}
        else
          {:halt, {acc, used}}
        end
      end)

    Enum.reverse(selected)
  end

  defp format(items, _request) do
    context =
      items
      |> Enum.map(&format_item/1)
      |> Enum.join("\n\n")

    sources =
      Enum.map(items, fn item ->
        %{
          type: source_type(item),
          id: source_id(item),
          trust_tier: Map.get(item, :trust_tier, "agent_derived")
        }
      end)

    %{
      assembled_context: context,
      sources: sources,
      token_count: estimate_tokens(context)
    }
  end

  defp format_item(%EpisodicEvent{summary: summary}), do: "[episodic] #{summary}"

  defp format_item(%SemanticFact{subject: s, predicate: p, object: o}),
    do: "[semantic] #{s} #{p} #{o}"

  defp format_item(%{type: :episodic, summary: summary}), do: "[episodic] #{summary}"

  defp format_item(%{type: :semantic, subject: s, predicate: p, object: o}),
    do: "[semantic] #{s} #{p} #{o}"

  defp format_item(%{type: :working, key: key, value: value}),
    do: "[working] #{key}: #{inspect(value)}"

  defp format_item(%{type: :procedural, content: content}), do: "[procedural] #{content}"
  defp format_item(_), do: ""

  defp source_type(%EpisodicEvent{}), do: "episodic"
  defp source_type(%SemanticFact{}), do: "semantic"
  defp source_type(%{type: type}), do: to_string(type)

  defp source_id(%EpisodicEvent{id: id}), do: id
  defp source_id(%SemanticFact{id: id}), do: id
  defp source_id(%{id: id}), do: id
  defp source_id(%{key: key}), do: "working/#{key}"

  defp estimate_tokens(text) do
    div(String.length(text), 4)
  end

  defp emit_stage(stage, count) do
    :telemetry.execute([:jiyi, :retrieval, :stage], %{count: count}, %{stage: stage})
  end
end
