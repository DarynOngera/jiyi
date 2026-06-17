defmodule Jiyi.Schemas.SessionCheckpoint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:session_id, :string, autogenerate: false}
  schema "session_checkpoints" do
    field(:working_memory, :map, default: %{})
    field(:updated_at, :utc_datetime_usec)
  end

  def changeset(checkpoint \\ %__MODULE__{}, attrs) do
    checkpoint
    |> cast(attrs, [:session_id, :working_memory, :updated_at])
    |> validate_required([:session_id, :working_memory, :updated_at])
  end
end
