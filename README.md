# Jiyi

A durable, context-aware memory service for autonomous agents.

Jiyi stores and retrieves three kinds of memory:

- **Episodic events** – time-ordered observations with vector embeddings and provenance.
- **Semantic facts** – subject/predicate/object triples with validity windows.
- **Working memory** – per-session, short-term key/value state.

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
| `JIYI_API_TOKEN` | `dev-token-change-me` | Bearer token for HTTP endpoints |
| `JIYI_EMBEDDING_ENDPOINT` | `http://localhost:8000/embed` | Local embedding service URL |

## Running

```bash
mix run --no-halt
```

HTTP endpoints:

- `POST /context/assemble` – body: `agent_id`, `session_id`, `task`, optional `token_budget` and `memory_scopes`.
- `POST /memory/write` – body: `type`, `agent_id`, `content`, `provenance`, `scope`, optional `session_id`.

Both require `Authorization: Bearer <JIYI_API_TOKEN>`.

## Testing

```bash
# Run the suite (requires a configured test database)
mix test

# Run non-DB smoke tests only
mix test --no-start test/jiyi_test.exs test/jiyi/api/router_test.exs test/jiyi/retrieval_test.exs
```

## Architecture

See `TASK.md` for implementation phases and `AGENTS.md` for contributor/agent conventions.
