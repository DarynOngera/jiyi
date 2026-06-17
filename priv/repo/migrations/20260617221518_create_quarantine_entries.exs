defmodule Jiyi.Repo.Migrations.CreateQuarantineEntries do
  use Ecto.Migration

  def change do
    create table(:quarantine_entries, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:target_table, :text, null: false)
      add(:payload, :jsonb, null: false)
      add(:reason, :text, null: false)
      add(:status, :text, null: false, default: "pending")
      add(:created_at, :timestamptz, null: false)
      add(:reviewed_at, :timestamptz)
    end
  end
end
