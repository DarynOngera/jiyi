defmodule Jiyi.Repo.Migrations.CreateMcpSessionTokens do
  use Ecto.Migration

  def change do
    create table(:mcp_session_tokens, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:token_hash, :text, null: false)
      add(:agent_id, :text, null: false)
      add(:org_id, :text)
      add(:expires_at, :timestamptz, null: false)
      add(:inserted_at, :timestamptz, null: false, default: fragment("now()"))
    end

    create(unique_index(:mcp_session_tokens, [:token_hash]))
    create(index(:mcp_session_tokens, [:agent_id]))
  end
end
