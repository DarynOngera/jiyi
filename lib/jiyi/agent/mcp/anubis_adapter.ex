defmodule Jiyi.Agent.MCP.AnubisAdapter do
  @moduledoc """
  Jiyi.Agent.MCP.Adapter implementation backed by Anubis.Client.
  """

  @behaviour Jiyi.Agent.MCP.Adapter

  alias Jiyi.Agent.Config

  @impl true
  def start_link(opts) do
    Anubis.Client.start_link(opts)
  end

  @impl true
  def await_ready(name, timeout_ms) do
    Anubis.Client.await_ready(name, timeout: timeout_ms)
  end

  @impl true
  def call_tool(name, tool, args) do
    case Anubis.Client.call_tool(name, tool, args) do
      {:ok, %Anubis.MCP.Response{result: result}} -> unwrap_tool_result(result)
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def build_transport(%Config{transport: :mcp_http, endpoint: endpoint}) do
    uri = URI.parse(endpoint)
    base_url = "#{uri.scheme}://#{uri.host}:#{uri.port}"
    mcp_path = uri.path || "/"

    {:streamable_http, base_url: base_url, mcp_path: mcp_path, enable_sse: true}
  end

  def build_transport(%Config{transport: :mcp_stdio}) do
    cwd = File.cwd!()

    {:stdio,
     command: "elixir",
     args: ["-S", "mix", "run", "--no-halt"],
     cwd: cwd,
     env: %{
       "JIYI_HTTP_PORT" => "0",
       "JIYI_MCP_TRANSPORT" => "stdio"
     }}
  end

  defp unwrap_tool_result(%{"content" => [%{"type" => "text", "text" => text} | _]} = result) do
    case Jason.decode(text) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:ok, result}
    end
  end

  defp unwrap_tool_result(result), do: {:ok, result}
end
