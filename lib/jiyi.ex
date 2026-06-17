defmodule Jiyi do
  @moduledoc """
  Public API for the Jiyi memory service.
  """

  alias Jiyi.Memory.{EpisodicStore, SemanticStore, SessionSupervisor, SessionState}

  def write_memory(%{type: "episodic"} = request) do
    attrs =
      %{
        agent_id: request.agent_id,
        session_id: Map.fetch!(request, :session_id),
        summary: get_in(request.content, ["summary"]) || "",
        raw_ref: get_in(request.content, ["raw_ref"]),
        provenance_source: get_in(request.provenance, ["source"]),
        ingestion_method: get_in(request.provenance, ["ingestion_method"]),
        trust_tier: get_in(request.provenance, ["trust_tier"]),
        scope: request.scope
      }
      |> maybe_add_embedding()

    EpisodicStore.write(attrs)
  end

  def write_memory(%{type: "semantic"} = request) do
    attrs =
      %{
        subject: get_in(request.content, ["subject"]) || "",
        predicate: get_in(request.content, ["predicate"]) || "",
        object: get_in(request.content, ["object"]) || "",
        agent_id: request.agent_id,
        provenance_source: get_in(request.provenance, ["source"]),
        ingestion_method: get_in(request.provenance, ["ingestion_method"]),
        trust_tier: get_in(request.provenance, ["trust_tier"]),
        scope: request.scope
      }
      |> maybe_add_embedding()

    SemanticStore.write(attrs)
  end

  def write_memory(%{type: "working"} = request) do
    session_id = Map.fetch!(request, :session_id)
    content = request.content

    with {:ok, _pid} <- ensure_session(session_id),
         :ok <- SessionState.put(session_id, :working, content) do
      {:ok, session_id}
    end
  end

  def write_memory(_request) do
    {:error, :unknown_memory_type}
  end

  def assemble_context(request) do
    Jiyi.Retrieval.assemble(request)
  end

  defp maybe_add_embedding(attrs) do
    text = extract_text(attrs)

    case Jiyi.EmbeddingClient.CircuitBreaker.embed(text) do
      {:ok, vector} -> Map.put(attrs, :embedding, vector)
      {:error, _} -> attrs
    end
  end

  defp extract_text(%{summary: summary}), do: summary

  defp extract_text(%{subject: s, predicate: p, object: o}) do
    "#{s} #{p} #{o}"
  end

  defp ensure_session(session_id) do
    case Registry.lookup(Jiyi.Registry, {Jiyi.Memory.SessionState, session_id}) do
      [] -> SessionSupervisor.start_session(session_id)
      [{pid, _}] -> {:ok, pid}
    end
  end
end
