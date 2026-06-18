defmodule Jiyi.Schemas.SemanticFact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "semantic_facts" do
    field(:subject, :string)
    field(:predicate, :string)
    field(:object, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:valid_from, :utc_datetime_usec)
    field(:valid_until, :utc_datetime_usec)
    field(:learned_at, :utc_datetime_usec)

    field(:agent_id, :string)
    field(:provenance_source, :string)
    field(:ingestion_method, :string)
    field(:trust_tier, :string)
    field(:scope, :string)
    field(:content_hash, :string)
    field(:relevance, :float, virtual: true)
  end

  def changeset(fact \\ %__MODULE__{}, attrs) do
    fact
    |> cast(attrs, [
      :subject,
      :predicate,
      :object,
      :embedding,
      :valid_from,
      :valid_until,
      :learned_at,
      :agent_id,
      :provenance_source,
      :ingestion_method,
      :trust_tier,
      :scope,
      :content_hash
    ])
    |> validate_required([
      :subject,
      :predicate,
      :object,
      :valid_from,
      :learned_at,
      :agent_id,
      :provenance_source,
      :ingestion_method,
      :trust_tier,
      :scope,
      :content_hash
    ])
  end
end
