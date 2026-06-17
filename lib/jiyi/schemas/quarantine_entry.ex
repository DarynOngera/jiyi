defmodule Jiyi.Schemas.QuarantineEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "quarantine_entries" do
    field(:target_table, :string)
    field(:payload, :map)
    field(:reason, :string)
    field(:status, :string, default: "pending")
    field(:created_at, :utc_datetime_usec)
    field(:reviewed_at, :utc_datetime_usec)
  end

  def changeset(entry \\ %__MODULE__{}, attrs) do
    entry
    |> cast(attrs, [:target_table, :payload, :reason, :status, :created_at, :reviewed_at])
    |> validate_required([:target_table, :payload, :reason, :status, :created_at])
    |> validate_inclusion(:status, ["pending", "promoted", "rejected"])
    |> validate_inclusion(:target_table, ["episodic_events", "semantic_facts"])
  end
end
