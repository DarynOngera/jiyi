defmodule Jiyi.EmbeddingServer.HTTP do
  @moduledoc """
  Minimal HTTP interface for the local embedding server.

  Exposes POST /embed returning {"embedding": [...]}.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST", path_info: ["embed"]} = conn, _opts) do
    with {:read, {:ok, body, conn}} <- {:read, read_body(conn)},
         {:decode, {:ok, %{"text" => text}}} when is_binary(text) <- {:decode, Jason.decode(body)},
         {:embed, {:ok, vector}} <- {:embed, Jiyi.EmbeddingServer.embed(text)} do
      send_json(conn, 200, %{embedding: vector})
    else
      {:read, _} ->
        send_json(conn, 400, %{error: "invalid_body"})

      {:decode, _} ->
        send_json(conn, 400, %{error: "expected JSON body with 'text' field"})

      {:embed, {:error, reason}} ->
        send_json(conn, 503, %{error: to_string(reason)})
    end
  end

  def call(conn, _opts) do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
