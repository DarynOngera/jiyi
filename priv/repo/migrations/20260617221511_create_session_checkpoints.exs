defmodule Jiyi.Repo.Migrations.CreateSessionCheckpoints do
  use Ecto.Migration

  def change do
    create table(:session_checkpoints, primary_key: false) do
      add(:session_id, :text, primary_key: true, null: false)
      add(:working_memory, :jsonb, null: false, default: "'{}'")
      add(:updated_at, :timestamptz, null: false)
    end
  end
end
