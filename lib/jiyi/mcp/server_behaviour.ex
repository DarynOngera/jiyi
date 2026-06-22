defmodule Jiyi.MCP.ServerBehaviour do
  @moduledoc """
  Contract for Jiyi MCP server modules.

  Any module used as :mcp_server_module must:

  - Accept `{Module, transport: term()}` as a child spec.
  - Expose the tools defined in `Jiyi.MCP.Tools` via whatever MCP framework
    it wraps.
  - Delegate tool execution to `Jiyi.MCP.Tools.context_assemble/1` and
    `Jiyi.MCP.Tools.memory_write/1`, passing string-keyed args maps.
  """
end
