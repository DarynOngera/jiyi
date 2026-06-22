defmodule Jiyi.API.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    http_port = Application.fetch_env!(:jiyi, :http_port)
    mcp_transport = Application.fetch_env!(:jiyi, :mcp_transport)

    mcp_server =
      Application.get_env(:jiyi, :mcp_server_module, Jiyi.API.MCPServer)

    children = [
      {Bandit, plug: Jiyi.API.Router, scheme: :http, port: http_port},
      {mcp_server, transport: mcp_transport}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
