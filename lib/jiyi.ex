defmodule Jiyi do
  @moduledoc """
  Public API for the Jiyi memory service.
  """

  alias Jiyi.Memory.{EpisodicStore, SemanticStore, SessionSupervisor, SessionState}

  @memory_types ["episodic", "semantic", "working"]
  @trust_tiers ["human_asserted", "agent_derived", "external_untrusted"]
  @scopes ["agent_private", "session_shared", "org_shared"]

  def write_memory(request) do
    with :ok <- validate_request(request) do
      do_write_memory(request)
    end
  end

  defp do_write_memory(%{type: "episodic"} = request) do
    case Map.fetch(request, :session_id) do
      {:ok, session_id} when is_binary(session_id) ->
        attrs =
          %{
            agent_id: request.agent_id,
            session_id: session_id,
            org_id: Map.get(request, :org_id),
            summary: get_in(request.content, ["summary"]) || "",
            raw_ref: get_in(request.content, ["raw_ref"]),
            provenance_source: get_in(request.provenance, ["source"]),
            ingestion_method: get_in(request.provenance, ["ingestion_method"]),
            trust_tier: get_in(request.provenance, ["trust_tier"]),
            scope: request.scope
          }
          |> maybe_add_embedding()

        with attrs when is_map(attrs) <- attrs do
          EpisodicStore.write(attrs)
        end

      _ ->
        {:error, :missing_session_id}
    end
  end

  defp do_write_memory(%{type: "semantic"} = request) do
    attrs =
      %{
        subject: get_in(request.content, ["subject"]) || "",
        predicate: get_in(request.content, ["predicate"]) || "",
        object: get_in(request.content, ["object"]) || "",
        agent_id: request.agent_id,
        session_id: Map.get(request, :session_id),
        org_id: Map.get(request, :org_id),
        provenance_source: get_in(request.provenance, ["source"]),
        ingestion_method: get_in(request.provenance, ["ingestion_method"]),
        trust_tier: get_in(request.provenance, ["trust_tier"]),
        scope: request.scope
      }
      |> maybe_add_embedding()

    with attrs when is_map(attrs) <- attrs do
      SemanticStore.write(attrs)
    end
  end

  defp do_write_memory(%{type: "working"} = request) do
    case Map.fetch(request, :session_id) do
      {:ok, session_id} when is_binary(session_id) ->
        content = request.content

        with {:ok, _pid} <- ensure_session(session_id),
             :ok <- SessionState.put(session_id, :working, content) do
          {:ok, %{status: "written", id: session_id}}
        end

      _ ->
        {:error, :missing_session_id}
    end
  end

  defp do_write_memory(_request) do
    {:error, :unknown_memory_type}
  end

  defp validate_request(request) do
    with :ok <- validate_type(request),
         :ok <- validate_scope(request),
         :ok <- validate_trust_tier(request),
         :ok <- validate_content_shape(request) do
      :ok
    end
  end

  defp validate_type(%{type: type}) when type in @memory_types, do: :ok
  defp validate_type(%{type: _}), do: {:error, :invalid_memory_type}
  defp validate_type(_), do: {:error, :missing_memory_type}

  defp validate_scope(%{scope: scope}) when scope in @scopes, do: :ok
  defp validate_scope(%{scope: _}), do: {:error, :invalid_scope}
  defp validate_scope(_), do: {:error, :missing_scope}

  defp validate_trust_tier(%{provenance: %{"trust_tier" => tier}}) when tier in @trust_tiers,
    do: :ok

  defp validate_trust_tier(%{provenance: %{"trust_tier" => _}}), do: {:error, :invalid_trust_tier}
  defp validate_trust_tier(_), do: {:error, :missing_trust_tier}

  defp validate_content_shape(%{type: "episodic", content: content}) do
    if is_map(content) and is_binary(Map.get(content, "summary")) and
         String.trim(Map.get(content, "summary")) != "" do
      :ok
    else
      {:error, :missing_summary}
    end
  end

  defp validate_content_shape(%{type: "semantic", scope: "session_shared"} = request) do
    session_id = Map.get(request, :session_id)

    if is_binary(session_id) and session_id != "" do
      validate_semantic_content(request)
    else
      {:error, :missing_session_id}
    end
  end

  defp validate_content_shape(%{type: "semantic", content: content}) do
    validate_semantic_content(%{content: content})
  end

  defp validate_content_shape(%{type: "working", content: content}) when is_map(content),
    do: :ok

  defp validate_content_shape(%{type: "working"}), do: {:error, :missing_content}
  defp validate_content_shape(_), do: :ok

  defp validate_semantic_content(request) do
    content = Map.get(request, :content)

    if is_map(content) and
         required_string?(Map.get(content, "subject")) and
         required_string?(Map.get(content, "predicate")) and
         required_string?(Map.get(content, "object")) do
      :ok
    else
      {:error, :missing_semantic_fields}
    end
  end

  defp required_string?(value), do: is_binary(value) and String.trim(value) != ""

  def assemble_context(request) do
    Jiyi.Retrieval.assemble(request)
  end

  defp maybe_add_embedding(attrs) do
    text = extract_text(attrs)

    case Jiyi.EmbeddingClient.CircuitBreaker.embed(text) do
      {:ok, vector} ->
        Map.put(attrs, :embedding, vector)

      {:error, reason} ->
        require Logger
        Logger.warning("Embedding generation failed: #{inspect(reason)} for text: #{text}")
        {:error, :embedding_failed}
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
