defmodule Jiyi.API.MCPPlug do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts) do
    mcp_opts = Anubis.Server.Transport.StreamableHTTP.Plug.init(server: Jiyi.API.MCPServer)
    Keyword.put(opts, :mcp_opts, mcp_opts)
  end

  @impl true
  def call(conn, opts) do
    case Application.fetch_env!(:jiyi, :mcp_transport) do
      :stdio -> not_enabled(conn)
      _ -> Anubis.Server.Transport.StreamableHTTP.Plug.call(conn, opts[:mcp_opts])
    end
  end

  defp not_enabled(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "mcp_not_enabled"}))
  end
end
