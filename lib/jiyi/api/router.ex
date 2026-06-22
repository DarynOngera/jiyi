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
         {:ok, request} <- Jiyi.Auth.authenticate(conn.assigns.api_token, request),
         result <- Jiyi.Retrieval.assemble(request) do
      send_json(conn, 200, result)
    else
      {:error, :agent_id_mismatch} ->
        send_json(conn, 403, %{error: "agent_id_mismatch"})

      {:error, reason} when reason in [:invalid_token, :missing_token] ->
        send_json(conn, 401, %{error: reason})

      {:error, reason} ->
        send_json(conn, 400, %{error: reason})
    end
  end

  post "/memory/write" do
    with {:ok, request} <- validate_write(conn.body_params),
         {:ok, request} <- Jiyi.Auth.authenticate(conn.assigns.api_token, request),
         {:ok, response} <- Jiyi.write_memory(request) do
      send_json(conn, 200, response)
    else
      {:error, :agent_id_mismatch} ->
        send_json(conn, 403, %{error: "agent_id_mismatch"})

      {:error, reason} when reason in [:invalid_token, :missing_token] ->
        send_json(conn, 401, %{error: reason})

      {:error, reason} ->
        send_json(conn, 400, %{error: reason})

      {:quarantined, id} ->
        send_json(conn, 200, %{status: "quarantined", id: id})

      {:duplicate, id} ->
        send_json(conn, 200, %{status: "duplicate", id: id})
    end
  end

  post "/auth/mcp-token" do
    with {:ok, request} <- validate_mcp_token_request(conn.body_params),
         {:ok, request} <- Jiyi.Auth.authenticate(conn.assigns.api_token, request),
         {:ok, token} <- Jiyi.Auth.issue_mcp_token(request.agent_id, request.org_id) do
      send_json(conn, 200, %{token: token, expires_in: 300})
    else
      {:error, :agent_id_mismatch} ->
        send_json(conn, 403, %{error: "agent_id_mismatch"})

      {:error, reason} when reason in [:invalid_token, :missing_token] ->
        send_json(conn, 401, %{error: reason})

      {:error, reason} ->
        send_json(conn, 400, %{error: reason})
    end
  end

  post "/admin/agents" do
    if Jiyi.Auth.admin_token?(conn.assigns.api_token) do
      with {:ok, request} <- validate_register_agent_request(conn.body_params),
           {:ok, token} <- Jiyi.Auth.create_agent_key(request.agent_id, request.org_id) do
        send_json(conn, 201, %{agent_id: request.agent_id, api_key: token})
      else
        {:error, reason} -> send_json(conn, 400, %{error: reason})
      end
    else
      send_json(conn, 403, %{error: "admin_required"})
    end
  end

  get "/admin/quarantine" do
    if Jiyi.Auth.admin_token?(conn.assigns.api_token) do
      entries =
        Jiyi.Memory.Quarantine.list_pending()
        |> Enum.map(fn entry ->
          %{
            id: entry.id,
            target_table: entry.target_table,
            reason: entry.reason,
            created_at: entry.created_at,
            payload: entry.payload
          }
        end)

      send_json(conn, 200, %{entries: entries})
    else
      send_json(conn, 403, %{error: "admin_required"})
    end
  end

  post "/admin/quarantine/:id/promote" do
    if Jiyi.Auth.admin_token?(conn.assigns.api_token) do
      case Jiyi.Memory.Quarantine.promote(conn.params["id"]) do
        {:ok, _} ->
          send_json(conn, 200, %{status: "promoted", id: conn.params["id"]})

        {:error, :already_reviewed} ->
          send_json(conn, 409, %{error: "already_reviewed"})

        {:error, reason} ->
          send_json(conn, 400, %{error: reason})
      end
    else
      send_json(conn, 403, %{error: "admin_required"})
    end
  end

  post "/admin/quarantine/:id/reject" do
    if Jiyi.Auth.admin_token?(conn.assigns.api_token) do
      case Jiyi.Memory.Quarantine.reject(conn.params["id"]) do
        :ok ->
          send_json(conn, 200, %{status: "rejected", id: conn.params["id"]})

        {:error, :not_found} ->
          send_json(conn, 404, %{error: "not_found"})

        {:error, :already_reviewed} ->
          send_json(conn, 409, %{error: "already_reviewed"})

        {:error, reason} ->
          send_json(conn, 400, %{error: reason})
      end
    else
      send_json(conn, 403, %{error: "admin_required"})
    end
  end

  forward("/mcp", to: Jiyi.API.MCPPlug)

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp authenticate(conn, _opts) do
    if String.starts_with?(conn.request_path, "/mcp") do
      conn
    else
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] when is_binary(token) and token != "" ->
          Plug.Conn.assign(conn, :api_token, token)

        _ ->
          conn
          |> send_json(401, %{error: "unauthorized"})
          |> halt()
      end
    end
  end

  defp validate_assemble(params) do
    required = ["agent_id", "session_id", "task"]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      {:ok,
       %{
         agent_id: params["agent_id"],
         session_id: params["session_id"],
         org_id: Map.get(params, "org_id"),
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
         org_id: Map.get(params, "org_id"),
         content: params["content"],
         provenance: params["provenance"],
         scope: params["scope"]
       }}
    else
      {:error, :missing_fields}
    end
  end

  defp validate_mcp_token_request(params) do
    if Map.has_key?(params, "agent_id") do
      {:ok,
       %{
         agent_id: params["agent_id"],
         org_id: Map.get(params, "org_id")
       }}
    else
      {:error, :missing_fields}
    end
  end

  defp validate_register_agent_request(params) do
    if is_binary(Map.get(params, "agent_id")) and String.trim(params["agent_id"]) != "" do
      {:ok,
       %{
         agent_id: params["agent_id"],
         org_id: Map.get(params, "org_id")
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
