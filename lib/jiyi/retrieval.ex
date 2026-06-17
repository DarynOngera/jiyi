defmodule Jiyi.Retrieval do
  @moduledoc """
  Plain-module retrieval pipeline: route -> fan-out -> rank -> compress -> format.
  """

  alias Jiyi.Memory.{EpisodicStore, SemanticStore, SessionState}

  def assemble(request) do
    request = normalize_request(request)

    {episodic, semantic, working, procedural} = fan_out(request)

    ranked = rank(episodic ++ semantic ++ working ++ procedural, request)
    compressed = compress(ranked, request)
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

  defp fan_out(%{task: task} = request) do
    tasks = [
      Task.Supervisor.async(Jiyi.Retrieval.TaskSupervisor, fn ->
        {:episodic, safe_query(fn -> EpisodicStore.query([text: task], limit: 10) end)}
      end),
      Task.Supervisor.async(Jiyi.Retrieval.TaskSupervisor, fn ->
        {:semantic, safe_query(fn -> SemanticStore.query([text: task], limit: 10) end)}
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
    path = procedural_path(task)

    if path && File.exists?(path) do
      content = File.read!(path)
      [%{type: :procedural, content: content}]
    else
      []
    end
  end

  defp procedural_path(_task) do
    nil
  end

  defp rank(items, _request) do
    Enum.sort_by(items, &score/1, :desc)
  end

  defp score(%{trust_tier: "human_asserted"}), do: 1.0
  defp score(%{trust_tier: "agent_derived"}), do: 0.7
  defp score(%{trust_tier: "external_untrusted"}), do: 0.3
  defp score(%{type: :working}), do: 0.95
  defp score(%{type: :procedural}), do: 0.85
  defp score(_), do: 0.5

  defp compress(items, request) do
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
          type: to_string(item.type),
          id: Map.get(item, :id, "working/#{item[:key]}"),
          trust_tier: Map.get(item, :trust_tier, "agent_derived")
        }
      end)

    %{
      assembled_context: context,
      sources: sources,
      token_count: estimate_tokens(context)
    }
  end

  defp format_item(%{type: :episodic, summary: summary}), do: "[episodic] #{summary}"

  defp format_item(%{type: :semantic, subject: s, predicate: p, object: o}),
    do: "[semantic] #{s} #{p} #{o}"

  defp format_item(%{type: :working, key: key, value: value}),
    do: "[working] #{key}: #{inspect(value)}"

  defp format_item(%{type: :procedural, content: content}), do: "[procedural] #{content}"
  defp format_item(_), do: ""

  defp estimate_tokens(text) do
    div(String.length(text), 4)
  end
end
