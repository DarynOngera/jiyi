defmodule Jiyi.Schemas.EpisodicEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "episodic_events" do
    field(:agent_id, :string)
    field(:session_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:summary, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:raw_ref, :string)

    field(:provenance_source, :string)
    field(:ingestion_method, :string)
    field(:trust_tier, :string)
    field(:scope, :string)
    field(:content_hash, :string)
    field(:relevance, :float, virtual: true)
  end

  def changeset(event \\ %__MODULE__{}, attrs) do
    event
    |> cast(attrs, [
      :agent_id,
      :session_id,
      :occurred_at,
      :summary,
      :embedding,
      :raw_ref,
      :provenance_source,
      :ingestion_method,
      :trust_tier,
      :scope,
      :content_hash
    ])
    |> validate_required([
      :agent_id,
      :session_id,
      :occurred_at,
      :summary,
      :provenance_source,
      :ingestion_method,
      :trust_tier,
      :scope,
      :content_hash
    ])
  end
end
