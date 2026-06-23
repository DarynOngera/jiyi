# Jiyi

A durable, context-aware memory service for autonomous agents.

> Jìyì (记忆) - Translates to personal memory from Chinese.

Jiyi stores and retrieves four kinds of memory:

- **Episodic events** – time-ordered observations with vector embeddings and provenance.
- **Semantic facts** – subject/predicate/object triples with validity windows.
- **Working memory** – per-session, short-term key/value state.
- **Procedural memory** – git-backed playbook files read at assembly time.

It exposes both an HTTP API (`Plug` + `Bandit`) and an MCP server (`anubis_mcp`) so callers can `context/assemble` ranked memory or `memory/write` new entries.

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

## Quick start

Start the service (assumes Postgres and the configured embedding endpoint are running):

```bash
export JIYI_API_TOKEN="dev-token-change-me"
mix run --no-halt
```

### Local embedding server (optional)

Jiyi can optionally bundle its own embedding server using `BAAI/bge-base-en-v1.5` via Bumblebee. It is **opt-in** because loading a transformer model adds ~400 MB download, ~500 MB–1 GB RAM, and noticeable CPU usage. Enable it when you do not have a separate embedding service:

```bash
export JIYI_EMBEDDING_SERVER_ENABLED=true
export JIYI_EMBEDDING_ENDPOINT=http://localhost:8001/embed
mix run --no-halt
```

When enabled, the server listens on `JIYI_EMBEDDING_SERVER_PORT` (default `8001`) and exposes `POST /embed`. Jiyi's circuit breaker will use it automatically once `JIYI_EMBEDDING_ENDPOINT` points there.

Write a memory and read it back:

```bash
curl -X POST http://localhost:4000/memory/write \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JIYI_API_TOKEN" \
  -d '{
    "type": "semantic",
    "agent_id": "agent-1",
    "session_id": "session-1",
    "content": {"subject": "project", "predicate": "uses", "object": "Elixir"},
    "provenance": {"source": "user_message", "ingestion_method": "direct_write", "trust_tier": "human_asserted"},
    "scope": "session_shared"
  }'

curl -X POST http://localhost:4000/context/assemble \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JIYI_API_TOKEN" \
  -d '{"agent_id": "agent-1", "session_id": "session-1", "task": "What does the project use?"}'
```

### MCP

Jiyi also exposes the same operations as MCP tools. Use `stdio` (default) for clients that spawn the server process, or `streamable_http` to access MCP over the HTTP API:

```bash
# stdio
JIYI_MCP_TRANSPORT=stdio mix run --no-halt

# streamable HTTP
JIYI_MCP_TRANSPORT=streamable_http mix run --no-halt
```

With `streamable_http`, point an MCP client at `http://localhost:4000/mcp`.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `JIYI_DB_USER` | `postgres` | Postgres username |
| `JIYI_DB_PASSWORD` | `postgres` | Postgres password |
| `JIYI_DB_HOST` | `localhost` | Postgres host |
| `JIYI_DB_NAME` | `jiyi_dev` / `jiyi_test` | Database name |
| `JIYI_HTTP_PORT` | `4000` | HTTP API port |
| `JIYI_API_TOKEN` | `dev-token-change-me` | Shared admin bearer token for HTTP endpoints |
| `JIYI_EMBEDDING_ENDPOINT` | `http://localhost:8000/embed` (or `http://localhost:8001/embed` when the local server is enabled) | Embedding service URL |
| `JIYI_EMBEDDING_SERVER_ENABLED` | `false` | Start the bundled BGE embedding server |
| `JIYI_EMBEDDING_SERVER_PORT` | `8001` | Port for the bundled embedding server |
| `JIYI_EMBEDDING_MODEL_REPO` | `BAAI/bge-base-en-v1.5` | HuggingFace model repo |
| `JIYI_MCP_TRANSPORT` | `stdio` | MCP transport: `stdio` or `streamable_http` |
| `JIYI_MCP_HTTP_PORT` | `4001` | Dedicated MCP streamable HTTP port when enabled |

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

## Extending MCP providers

Jiyi uses Anubis by default for both the client-side MCP adapter and the server-side MCP server, but both sides are abstracted so a new provider can be added without changing business logic.

1. **Server side**: create `lib/jiyi/api/mcp_server_<provider>.ex` using the new framework's `use` macro. Expose two tools (`context_assemble` and `memory_write`) whose execution handlers delegate to `Jiyi.MCP.Tools.context_assemble/1` and `Jiyi.MCP.Tools.memory_write/1` with string-keyed args maps.

2. **Client side**: create `lib/jiyi/agent/mcp/<provider>_adapter.ex` implementing `@behaviour Jiyi.Agent.MCP.Adapter`. Move the framework-specific `start_link`, `await_ready`, `call_tool`, and transport-building code there.

3. **Wiring**: set the environment variables when starting Jiyi:

   ```bash
   export JIYI_MCP_SERVER_MODULE=Jiyi.API.MCPServerMyProvider
   export JIYI_MCP_CLIENT_ADAPTER=Jiyi.Agent.MCP.MyProviderAdapter
   ```

No existing modules need to change.

## Architecture

See `TASK.md` for implementation phases and `AGENTS.md` for contributor/agent conventions.
