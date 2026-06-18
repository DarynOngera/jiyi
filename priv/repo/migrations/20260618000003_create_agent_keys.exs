defmodule Jiyi.Repo.Migrations.CreateAgentKeys do
  use Ecto.Migration

  def change do
    create table(:agent_keys, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:key_hash, :text, null: false)
      add(:agent_id, :text, null: false)
      add(:org_id, :text)
      add(:inserted_at, :timestamptz, null: false, default: fragment("now()"))
    end

    create(unique_index(:agent_keys, [:key_hash]))
    create(index(:agent_keys, [:agent_id]))
  end
end
