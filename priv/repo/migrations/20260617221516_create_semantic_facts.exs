defmodule Jiyi.Repo.Migrations.CreateSemanticFacts do
  use Ecto.Migration

  def change do
    dimension = Application.fetch_env!(:jiyi, :embedding_dimension)

    create table(:semantic_facts, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:subject, :text, null: false)
      add(:predicate, :text, null: false)
      add(:object, :text, null: false)
      add(:embedding, :vector, size: dimension)
      add(:valid_from, :timestamptz, null: false)
      add(:valid_until, :timestamptz)
      add(:learned_at, :timestamptz, null: false)

      add(:agent_id, :text, null: false)
      add(:provenance_source, :text, null: false)
      add(:ingestion_method, :text, null: false)
      add(:trust_tier, :text, null: false)
      add(:scope, :text, null: false)
      add(:content_hash, :text, null: false)
    end

    execute(
      "CREATE INDEX semantic_facts_search ON semantic_facts USING GIN (to_tsvector('english', subject || ' ' || predicate || ' ' || object))"
    )

    execute(
      "CREATE INDEX semantic_facts_embedding_idx ON semantic_facts USING hnsw (embedding vector_l2_ops)"
    )

    create(index(:semantic_facts, [:subject, :predicate]))
    create(index(:semantic_facts, [:content_hash]))
  end
end
