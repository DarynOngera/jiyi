defmodule Jiyi.Repo.Migrations.AddOrgIdToMemoryTables do
  use Ecto.Migration

  def change do
    alter table(:episodic_events) do
      add(:org_id, :text)
    end

    alter table(:semantic_facts) do
      add(:org_id, :text)
    end

    create(index(:episodic_events, [:org_id]))
    create(index(:semantic_facts, [:org_id]))
  end
end
