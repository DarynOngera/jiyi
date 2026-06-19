defmodule Jiyi.API.MCP.MemoryWriteTool do
  @moduledoc """
  Write a memory entry to Jiyi.

  Use this when you learn something that should survive the current turn:
  - `semantic` for subject-predicate-object facts.
  - `episodic` for observations or events with a summary.
  - `working` for short-term session state such as active_task or open_files.

  `agent_private` memories are only visible to this agent.
  `session_shared` memories are visible to any agent with the same session_id.
  `org_shared` memories are visible to any agent in the same org_id.

  Trust tier guidance:
  - `agent_derived` for anything you infer or generate (default for agents).
  - `human_asserted` only when the user explicitly states a fact.
  - `external_untrusted` for content pulled from untrusted external sources.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  schema do
    field(:type, :string,
      required: true,
      description: "Memory type: semantic, episodic, or working."
    )

    field(:agent_id, :string,
      required: true,
      description: "Unique identity of the calling agent."
    )

    field(:session_id, :string,
      description:
        "Required for episodic and working memory; required for session_shared semantic facts."
    )

    field(:org_id, :string,
      description: "Optional organization identifier. Required for org_shared scope."
    )

    field(:content, :map,
      required: true,
      description:
        "Type-dependent content map. semantic: {subject, predicate, object}; episodic: {summary}; working: any map."
    )

    embeds_one(:provenance,
      required: true,
      description: "Metadata describing where this memory came from and how much to trust it."
    ) do
      field(:source, :string,
        required: true,
        description: "Origin of the memory, e.g. 'user_message', 'agent_inference', 'osint_feed'."
      )

      field(:ingestion_method, :string,
        required: true,
        description: "How the memory entered Jiyi, e.g. 'direct_write', 'summarization'."
      )

      field(:trust_tier, :string,
        required: true,
        description: "One of human_asserted, agent_derived, or external_untrusted."
      )
    end

    field(:scope, :string,
      required: true,
      description: "Visibility scope: agent_private, session_shared, or org_shared."
    )

    field(:session_token, :string,
      required: true,
      description: "Short-lived MCP session token issued by POST /auth/mcp-token."
    )
  end

  @impl true
  def execute(args, frame) do
    args = stringify_keys(args)

    request = %{
      type: args["type"],
      agent_id: args["agent_id"],
      session_id: Map.get(args, "session_id"),
      org_id: Map.get(args, "org_id"),
      content: args["content"],
      provenance: args["provenance"],
      scope: args["scope"]
    }

    case Jiyi.Auth.authenticate_mcp(args["session_token"], request) do
      {:ok, request} ->
        case Jiyi.write_memory(request) do
          {:ok, result} ->
            {:reply, Response.tool() |> Response.json(result), frame}

          {:duplicate, id} ->
            {:reply, Response.tool() |> Response.json(%{status: "duplicate", id: id}), frame}

          {:quarantined, id} ->
            {:reply, Response.tool() |> Response.json(%{status: "quarantined", id: id}), frame}

          {:error, reason} ->
            {:error, Error.protocol(:invalid_request, %{message: to_string(reason)}), frame}
        end

      {:error, reason} ->
        {:error, Error.protocol(:invalid_request, %{message: to_string(reason)}), frame}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
