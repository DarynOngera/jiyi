defmodule Jiyi.API.MCPServer do
  @moduledoc """
  Hermes MCP server exposing the same operations as the HTTP router.
  """

  use Hermes.Server,
    name: "jiyi",
    version: "0.1.0",
    capabilities: [:tools]

  component(Jiyi.API.MCP.ContextAssembleTool)
  component(Jiyi.API.MCP.MemoryWriteTool)
end
