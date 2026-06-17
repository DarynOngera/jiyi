defmodule Jiyi.API.Router do
  @moduledoc """
  Plug router exposing the HTTP transport for Jiyi.
  """

  use Plug.Router

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:authenticate)
  plug(:dispatch)

  post "/context/assemble" do
    with {:ok, request} <- validate_assemble(conn.body_params),
         result <- Jiyi.Retrieval.assemble(request) do
      send_json(conn, 200, result)
    else
      {:error, reason} -> send_json(conn, 400, %{error: reason})
    end
  end

  post "/memory/write" do
    with {:ok, request} <- validate_write(conn.body_params),
         {:ok, response} <- Jiyi.write_memory(request) do
      send_json(conn, 200, response)
    else
      {:error, reason} -> send_json(conn, 400, %{error: reason})
      {:quarantined, id} -> send_json(conn, 200, %{status: "quarantined", id: id})
      {:duplicate, id} -> send_json(conn, 200, %{status: "duplicate", id: id})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp authenticate(conn, _opts) do
    expected = Application.fetch_env!(:jiyi, :api_token)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> ^expected] ->
        conn

      _ ->
        conn
        |> send_json(401, %{error: "unauthorized"})
        |> halt()
    end
  end

  defp validate_assemble(params) do
    required = ["agent_id", "session_id", "task"]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      {:ok,
       %{
         agent_id: params["agent_id"],
         session_id: params["session_id"],
         task: params["task"],
         token_budget: Map.get(params, "token_budget", 4000),
         memory_scopes:
           Map.get(params, "memory_scopes", ["agent_private", "session_shared", "org_shared"])
       }}
    else
      {:error, :missing_fields}
    end
  end

  defp validate_write(params) do
    required = ["type", "agent_id", "content", "provenance", "scope"]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      {:ok,
       %{
         type: params["type"],
         agent_id: params["agent_id"],
         session_id: Map.get(params, "session_id"),
         content: params["content"],
         provenance: params["provenance"],
         scope: params["scope"]
       }}
    else
      {:error, :missing_fields}
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
