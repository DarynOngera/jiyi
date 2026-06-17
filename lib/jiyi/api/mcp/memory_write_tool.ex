defmodule Jiyi.API.MCP.MemoryWriteTool do
  @moduledoc "Write a memory event, fact, or working-memory value"

  use Hermes.Server.Component, type: :tool

  schema do
    field(:type, {:required, :string})
    field(:agent_id, {:required, :string})
    field(:session_id, :string)
    field(:content, {:required, :map})

    field :provenance, {:required, :map} do
      field(:source, {:required, :string})
      field(:ingestion_method, {:required, :string})
      field(:trust_tier, {:required, :string})
    end

    field(:scope, {:required, :string})
  end

  @impl Hermes.Server.Component.Tool
  def execute(args, _frame) do
    request = %{
      type: args["type"],
      agent_id: args["agent_id"],
      session_id: Map.get(args, "session_id"),
      content: args["content"],
      provenance: args["provenance"],
      scope: args["scope"]
    }

    case Jiyi.write_memory(request) do
      {:ok, id} -> {:ok, %{status: "written", id: id}}
      {:duplicate, id} -> {:ok, %{status: "duplicate", id: id}}
      {:quarantined, id} -> {:ok, %{status: "quarantined", id: id}}
      {:error, reason} -> {:error, to_string(reason)}
    end
  end
end
