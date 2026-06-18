defmodule Jiyi.Schemas.McpSessionToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "mcp_session_tokens" do
    field(:token_hash, :string)
    field(:agent_id, :string)
    field(:org_id, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:inserted_at, :utc_datetime_usec)
  end

  def changeset(token \\ %__MODULE__{}, attrs) do
    token
    |> cast(attrs, [:token_hash, :agent_id, :org_id, :expires_at, :inserted_at])
    |> validate_required([:token_hash, :agent_id, :expires_at, :inserted_at])
    |> unique_constraint(:token_hash)
  end
end
