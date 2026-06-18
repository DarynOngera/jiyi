defmodule Jiyi.API.MCP.ContextAssembleTool do
  @moduledoc "Assemble ranked context from memory stores"

  use Hermes.Server.Component, type: :tool

  schema do
    field(:agent_id, {:required, :string})
    field(:session_id, {:required, :string})
    field(:task, {:required, :string})
    field(:token_budget, :integer, default: 4000)
    field(:api_token, {:required, :string})

    field(:memory_scopes, {:list, :string},
      default: ["agent_private", "session_shared", "org_shared"]
    )
  end

  @impl Hermes.Server.Component.Tool
  def execute(args, _frame) do
    with :ok <- authenticate(args) do
      request = %{
        agent_id: args["agent_id"],
        session_id: args["session_id"],
        task: args["task"],
        token_budget: Map.get(args, "token_budget", 4000),
        memory_scopes:
          Map.get(args, "memory_scopes", ["agent_private", "session_shared", "org_shared"])
      }

      {:ok, Jiyi.Retrieval.assemble(request)}
    end
  end

  defp authenticate(args) do
    expected = Application.fetch_env!(:jiyi, :api_token)

    if args["api_token"] == expected do
      :ok
    else
      {:error, "unauthorized"}
    end
  end
end
