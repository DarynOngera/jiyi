# Jiyi

A durable, context-aware memory service for autonomous agents.

> Jìyì (记忆) - Translates to personal memory from Chinese.

Jiyi stores and retrieves four kinds of memory:

- **Episodic events** – time-ordered observations with vector embeddings and provenance.
- **Semantic facts** – subject/predicate/object triples with validity windows.
- **Working memory** – per-session, short-term key/value state.
- **Procedural memory** – git-backed playbook files read at assembly time.

It exposes both an HTTP API (`Plug` + `Bandit`) and an MCP server (`hermes_mcp`) so callers can `context/assemble` ranked memory or `memory/write` new entries.

## Requirements

- Elixir ~> 1.17 (tested on 1.19.5)
- Erlang/OTP ~> 27 (tested on OTP 28)
- PostgreSQL 16+ with the `pgvector` extension

## Setup

```bash
mix deps.get

# Configure Postgres credentials, then:
export JIYI_DB_USER="postgres"
export JIYI_DB_PASSWORD="..."
export JIYI_DB_HOST="localhost"
mix ecto.create
mix ecto.migrate
```

Default embedding dimension is `768`. Change it in `config/config.exs` before the first migration if you use a different model.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `JIYI_DB_USER` | `postgres` | Postgres username |
| `JIYI_DB_PASSWORD` | `postgres` | Postgres password |
| `JIYI_DB_HOST` | `localhost` | Postgres host |
| `JIYI_DB_NAME` | `jiyi_dev` / `jiyi_test` | Database name |
| `JIYI_HTTP_PORT` | `4000` | HTTP API port |
| `JIYI_API_TOKEN` | `dev-token-change-me` | Shared admin bearer token for HTTP endpoints |
| `JIYI_EMBEDDING_ENDPOINT` | `http://localhost:8000/embed` | Local embedding service URL |

## Authentication

Jiyi supports three credential types:

1. **Shared admin token** (`JIYI_API_TOKEN`) — full access; can assert any `trust_tier`, including `human_asserted`.
2. **Per-agent API keys** — stored in `agent_keys`; cryptographically bound to one `agent_id`; capped at `agent_derived` trust tier.
3. **MCP session tokens** — short-lived (5-minute) tokens issued via `POST /auth/mcp-token`; capped at `agent_derived` trust tier.

## Running

```bash
mix run --no-halt
```

HTTP endpoints:

- `POST /context/assemble` – body: `agent_id`, `session_id`, `task`, optional `org_id`, `token_budget`, and `memory_scopes`.
- `POST /memory/write` – body: `type`, `agent_id`, `content`, `provenance`, `scope`, optional `session_id` and `org_id`.
- `POST /auth/mcp-token` – body: `agent_id`, optional `org_id`. Issues a short-lived session token for MCP tools.

All HTTP endpoints require `Authorization: Bearer <token>`. The token may be the shared admin token or a per-agent API key.

## Memory scopes

Visibility is derived at query time from the caller's identity, not from the writer's declared scope:

- `agent_private` – visible when `agent_id` matches the caller.
- `session_shared` – visible when `session_id` matches the caller's session (any agent in the session).
- `org_shared` – visible when `org_id` matches the caller's org.

## Trust tiers and quarantine

Each memory write carries a `trust_tier` in `provenance`:

- `human_asserted` – highest trust; only the shared admin token may claim this.
- `agent_derived` – capped trust for per-agent keys and MCP session tokens.
- `external_untrusted` – always routed to quarantine for review.

Content is also scanned at write time and at context-assembly time for anomalous / instruction-like phrasing. Hits are routed to `Quarantine` rather than the live memory tables.

## Retrieval ranking

`context/assemble` ranks candidates by:

```
base_score(trust_tier) × recency_multiplier × relevance_multiplier
```

- `working` memory and `procedural` playbooks are pinned high by default.
- Recency uses exponential decay with a configurable half-life (default 8 hours).
- Relevance comes from PostgreSQL full-text ranking over indexed content.

## Testing

```bash
# Run the suite (requires a configured test database)
mix test

# Run a subset of tests quickly (still requires the test database)
mix test test/jiyi_test.exs test/jiyi/api/router_test.exs test/jiyi/retrieval_test.exs
```

## Architecture

See `TASK.md` for implementation phases and `AGENTS.md` for contributor/agent conventions.
