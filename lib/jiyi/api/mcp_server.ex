defmodule Jiyi.API.MCPServer do
  @moduledoc """
  Anubis MCP server exposing the same operations as the HTTP router.
  """

  use Anubis.Server,
    name: "jiyi",
    version: "0.1.0",
    capabilities: [:tools]

  component(Jiyi.API.MCP.ContextAssembleTool, name: "context_assemble")
  component(Jiyi.API.MCP.MemoryWriteTool, name: "memory_write")
end
