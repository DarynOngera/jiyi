defmodule Jiyi.Auth do
  @moduledoc """
  Authentication, caller identity binding, and trust-tier clamping.

  Supports a legacy shared token (config :jiyi, :api_token) for admin/system
  callers, plus per-agent API keys stored in the agent_keys table and short-lived
  MCP session tokens.

  Per-agent keys and MCP session tokens are cryptographically bound to a single
  agent_id and cap the trust tier the caller may claim: per-agent credentials
  cannot assert human_asserted.
  """

  import Ecto.Query

  alias Jiyi.Repo
  alias Jiyi.Schemas.{AgentKey, McpSessionToken}

  @mcp_token_ttl_seconds 300
  @mcp_trust_ceiling "agent_derived"

  def authenticate(token, request) when is_binary(token) do
    with :ok <- validate_token_present(token),
         {:ok, auth_context} <- resolve_token(token),
         :ok <- verify_agent_id(auth_context, request) do
      {:ok, request |> apply_org_id(auth_context) |> apply_trust_tier(auth_context)}
    end
  end

  def authenticate(_, _), do: {:error, :missing_token}

  def authenticate_mcp(token, request) when is_binary(token) do
    with :ok <- validate_token_present(token),
         {:ok, auth_context} <- resolve_mcp_token(token),
         :ok <- verify_agent_id(auth_context, request) do
      {:ok, request |> apply_org_id(auth_context) |> apply_trust_tier(auth_context)}
    end
  end

  def authenticate_mcp(_, _), do: {:error, :missing_token}

  def issue_mcp_token(agent_id, org_id \\ nil) do
    token = generate_token()
    hash = hash_token(token)
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, @mcp_token_ttl_seconds, :second)

    %McpSessionToken{}
    |> McpSessionToken.changeset(%{
      token_hash: hash,
      agent_id: agent_id,
      org_id: org_id,
      expires_at: expires_at,
      inserted_at: now
    })
    |> Repo.insert()
    |> case do
      {:ok, _} -> {:ok, token}
      error -> error
    end
  end

  defp validate_token_present(""), do: {:error, :missing_token}
  defp validate_token_present(nil), do: {:error, :missing_token}
  defp validate_token_present(_), do: :ok

  defp resolve_token(token) do
    if token == shared_token() do
      {:ok, %{type: :shared, trust_ceiling: nil}}
    else
      lookup_agent_key(token)
    end
  end

  defp shared_token do
    Application.fetch_env!(:jiyi, :api_token)
  end

  defp lookup_agent_key(token) do
    hash = hash_token(token)

    case Repo.one(from(k in AgentKey, where: k.key_hash == ^hash)) do
      nil ->
        {:error, :invalid_token}

      key ->
        {:ok,
         %{
           type: :agent,
           agent_id: key.agent_id,
           org_id: key.org_id,
           trust_ceiling: "agent_derived"
         }}
    end
  end

  defp resolve_mcp_token(token) do
    hash = hash_token(token)
    now = DateTime.utc_now()

    case Repo.one(from(t in McpSessionToken, where: t.token_hash == ^hash)) do
      nil ->
        {:error, :invalid_token}

      token_record ->
        if DateTime.compare(token_record.expires_at, now) == :gt do
          {:ok,
           %{
             type: :agent,
             agent_id: token_record.agent_id,
             org_id: token_record.org_id,
             trust_ceiling: @mcp_trust_ceiling
           }}
        else
          {:error, :expired_token}
        end
    end
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp verify_agent_id(%{type: :shared}, _request), do: :ok

  defp verify_agent_id(%{type: :agent, agent_id: expected}, request) do
    actual = Map.get(request, :agent_id)

    if actual == expected do
      :ok
    else
      {:error, :agent_id_mismatch}
    end
  end

  defp apply_org_id(request, %{type: :agent, org_id: org_id}) when is_binary(org_id) do
    case Map.get(request, :org_id) do
      nil -> Map.put(request, :org_id, org_id)
      _ -> request
    end
  end

  defp apply_org_id(request, _auth_context), do: request

  defp apply_trust_tier(request, %{trust_ceiling: nil}), do: request

  defp apply_trust_tier(request, %{trust_ceiling: ceiling}) do
    provenance = Map.get(request, :provenance) || %{}
    claimed = Map.get(provenance, "trust_tier")
    clamped = min_trust(claimed, ceiling)
    Map.put(request, :provenance, Map.put(provenance, "trust_tier", clamped))
  end

  defp min_trust(claimed, ceiling) do
    if trust_value(claimed) > trust_value(ceiling) do
      ceiling
    else
      claimed
    end
  end

  defp trust_value("human_asserted"), do: 1.0
  defp trust_value("agent_derived"), do: 0.7
  defp trust_value("external_untrusted"), do: 0.3
  defp trust_value(_), do: 0.0

  def register_key(token, agent_id, org_id \\ nil) do
    %AgentKey{}
    |> AgentKey.changeset(%{
      key_hash: hash_token(token),
      agent_id: agent_id,
      org_id: org_id,
      inserted_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end
end
