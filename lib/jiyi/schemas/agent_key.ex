defmodule Jiyi.Schemas.AgentKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "agent_keys" do
    field(:key_hash, :string)
    field(:agent_id, :string)
    field(:org_id, :string)
    field(:inserted_at, :utc_datetime_usec)
  end

  def changeset(key \\ %__MODULE__{}, attrs) do
    key
    |> cast(attrs, [:key_hash, :agent_id, :org_id, :inserted_at])
    |> validate_required([:key_hash, :agent_id, :inserted_at])
    |> unique_constraint(:key_hash)
  end
end
