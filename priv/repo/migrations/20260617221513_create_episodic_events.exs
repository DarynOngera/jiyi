defmodule Jiyi.Repo.Migrations.CreateEpisodicEvents do
  use Ecto.Migration

  def change do
    dimension = Application.fetch_env!(:jiyi, :embedding_dimension)

    create table(:episodic_events, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:agent_id, :text, null: false)
      add(:session_id, :text, null: false)
      add(:occurred_at, :timestamptz, null: false)
      add(:summary, :text, null: false)
      add(:embedding, :vector, size: dimension)
      add(:raw_ref, :text)

      add(:provenance_source, :text, null: false)
      add(:ingestion_method, :text, null: false)
      add(:trust_tier, :text, null: false)
      add(:scope, :text, null: false)
      add(:content_hash, :text, null: false)
    end

    execute(
      "CREATE INDEX episodic_events_summary_search ON episodic_events USING GIN (to_tsvector('english', summary))"
    )

    execute(
      "CREATE INDEX episodic_events_embedding_idx ON episodic_events USING hnsw (embedding vector_l2_ops)"
    )

    create(index(:episodic_events, [:agent_id, :occurred_at]))
    create(unique_index(:episodic_events, [:content_hash]))
  end
end
