defmodule Jiyi.API.MCP.ContextAssembleTool do
  @moduledoc """
  Assemble ranked context from Jiyi memory stores.

  Call this before answering a user request so you can see relevant prior
  facts, events, working memory, and playbooks for the current agent/session.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response

  schema do
    field(:agent_id, :string,
      required: true,
      description: "Unique identity of the calling agent."
    )

    field(:session_id, :string,
      required: true,
      description:
        "Shared session identifier. Other agents in the same session can see session_shared memories."
    )

    field(:org_id, :string,
      description: "Optional organization identifier. Enables org_shared memory visibility."
    )

    field(:task, :string,
      required: true,
      description:
        "The current task or user request. Jiyi ranks memories by relevance to this text."
    )

    field(:token_budget, :integer,
      default: 4000,
      description: "Maximum tokens to return in the assembled context."
    )

    field(:session_token, :string,
      required: true,
      description: "Short-lived MCP session token issued by POST /auth/mcp-token."
    )

    field(:memory_scopes, {:list, :string},
      default: ["agent_private", "session_shared", "org_shared"],
      description: "Which scopes to include: agent_private, session_shared, and/or org_shared."
    )
  end

  @impl true
  def execute(args, frame) do
    args = stringify_keys(args)

    request = %{
      agent_id: args["agent_id"],
      session_id: args["session_id"],
      org_id: Map.get(args, "org_id"),
      task: args["task"],
      token_budget: Map.get(args, "token_budget", 4000),
      memory_scopes:
        Map.get(args, "memory_scopes", ["agent_private", "session_shared", "org_shared"])
    }

    case Jiyi.Auth.authenticate_mcp(args["session_token"], request) do
      {:ok, request} ->
        result = Jiyi.Retrieval.assemble(request)
        {:reply, Response.tool() |> Response.json(result), frame}

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
