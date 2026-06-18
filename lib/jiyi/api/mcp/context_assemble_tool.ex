defmodule Jiyi.API.MCP.ContextAssembleTool do
  @moduledoc "Assemble ranked context from memory stores"

  use Hermes.Server.Component, type: :tool

  schema do
    field(:agent_id, {:required, :string})
    field(:session_id, {:required, :string})
    field(:org_id, :string)
    field(:task, {:required, :string})
    field(:token_budget, :integer, default: 4000)
    field(:session_token, {:required, :string})

    field(:memory_scopes, {:list, :string},
      default: ["agent_private", "session_shared", "org_shared"]
    )
  end

  @impl Hermes.Server.Component.Tool
  def execute(args, _frame) do
    request = %{
      agent_id: args["agent_id"],
      session_id: args["session_id"],
      org_id: Map.get(args, "org_id"),
      task: args["task"],
      token_budget: Map.get(args, "token_budget", 4000),
      memory_scopes:
        Map.get(args, "memory_scopes", ["agent_private", "session_shared", "org_shared"])
    }

    with {:ok, request} <- Jiyi.Auth.authenticate_mcp(args["session_token"], request) do
      {:ok, Jiyi.Retrieval.assemble(request)}
    end
  end
end
