defmodule Jiyi.Auth do
  @moduledoc """
  Authentication and caller identity binding.

  Supports a legacy shared token (config :jiyi, :api_token) for admin/system
  callers, plus per-agent API keys stored in the agent_keys table.

  Per-agent keys are cryptographically bound to a single agent_id. A caller
  using a per-agent key cannot self-report a different agent_id.
  """

  import Ecto.Query

  alias Jiyi.Repo
  alias Jiyi.Schemas.AgentKey

  def authenticate(token, request) when is_binary(token) do
    with :ok <- validate_token_present(token),
         {:ok, auth_context} <- resolve_token(token),
         :ok <- verify_agent_id(auth_context, request) do
      {:ok, apply_org_id(auth_context, request)}
    end
  end

  def authenticate(_, _), do: {:error, :missing_token}

  defp validate_token_present(""), do: {:error, :missing_token}
  defp validate_token_present(nil), do: {:error, :missing_token}
  defp validate_token_present(_), do: :ok

  defp resolve_token(token) do
    if token == shared_token() do
      {:ok, %{type: :shared}}
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
      nil -> {:error, :invalid_token}
      key -> {:ok, %{type: :agent, agent_id: key.agent_id, org_id: key.org_id}}
    end
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
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

  defp apply_org_id(%{type: :agent, org_id: org_id}, request) when is_binary(org_id) do
    case Map.get(request, :org_id) do
      nil -> Map.put(request, :org_id, org_id)
      _ -> request
    end
  end

  defp apply_org_id(_auth_context, request), do: request

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
