defmodule Jiyi.Repo.Migrations.AddSessionIdToSemanticFacts do
  use Ecto.Migration

  def change do
    alter table(:semantic_facts) do
      add(:session_id, :text)
    end

    create(index(:semantic_facts, [:agent_id, :session_id]))
  end
end
