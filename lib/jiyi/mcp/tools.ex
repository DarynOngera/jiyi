defmodule Jiyi.MCP.Tools do
  @moduledoc """
  Shared auth + business logic for MCP tool calls.

  Any MCP server provider should delegate tool execution to these functions,
  then format the returned `{:ok, result}` / `{:error, reason}` values for its
  framework's response types.
  """

  def context_assemble(args) do
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

  def memory_write(args) do
    request = %{
      type: args["type"],
      agent_id: args["agent_id"],
      session_id: Map.get(args, "session_id"),
      org_id: Map.get(args, "org_id"),
      content: args["content"],
      provenance: args["provenance"],
      scope: args["scope"]
    }

    with {:ok, request} <- Jiyi.Auth.authenticate_mcp(args["session_token"], request) do
      Jiyi.write_memory(request)
    end
  end
end
