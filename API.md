# Jiyi HTTP API Reference

All HTTP endpoints except `/mcp` require an `Authorization: Bearer <token>` header. The token may be the shared admin token (`JIYI_API_TOKEN`) or a per-agent API key issued via `POST /admin/agents`.

The `/mcp` endpoint bypasses bearer-token auth and relies on per-tool `session_token` arguments instead.

---

## Authentication

| Credential | How to obtain | Capabilities |
|------------|---------------|--------------|
| Shared admin token | `JIYI_API_TOKEN` env var | All HTTP routes; can assert `human_asserted` trust tier |
| Per-agent API key | `POST /admin/agents` | Scoped to one `agent_id`; capped at `agent_derived` trust tier |
| MCP session token | `POST /auth/mcp-token` | Short-lived (5 min); for MCP tool calls only |

---

## `POST /context/assemble`

Assemble ranked context from episodic, semantic, working, and procedural memory.

### Headers

```text
Authorization: Bearer <token>
Content-Type: application/json
```

### Request body

```json
{
  "agent_id": "agent-1",
  "session_id": "session-1",
  "org_id": "org-1",
  "task": "What do we know about the phishing report?",
  "token_budget": 4000,
  "memory_scopes": ["agent_private", "session_shared", "org_shared"]
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `agent_id` | yes | — | Caller identity |
| `session_id` | yes | — | Session for session_shared visibility |
| `org_id` | no | — | Organization for org_shared visibility |
| `task` | yes | — | Text used to rank memories |
| `token_budget` | no | `4000` | Approximate token budget for returned context |
| `memory_scopes` | no | `["agent_private", "session_shared", "org_shared"]` | Scopes to query |

### Response `200`

```json
{
  "assembled_context": "[episodic] User reported phishing email\n\n[semantic] user reported phishing email",
  "sources": [
    {"type": "episodic", "id": "...", "trust_tier": "agent_derived"},
    {"type": "semantic", "id": "...", "trust_tier": "agent_derived"}
  ],
  "token_count": 21,
  "blocked": false,
  "error": null
}
```

If a compositional anomaly is detected and isolated, the offending items are quarantined and removed from `assembled_context`.

### Curl

```bash
curl -X POST http://localhost:4000/context/assemble \
  -H "Authorization: Bearer $JIYI_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "agent-1",
    "session_id": "session-1",
    "task": "What do we know about the phishing report?"
  }'
```

---

## `POST /memory/write`

Write a semantic fact, episodic event, or working-memory entry.

### Headers

```text
Authorization: Bearer <token>
Content-Type: application/json
```

### Request body

**Semantic fact**

```json
{
  "type": "semantic",
  "agent_id": "agent-1",
  "session_id": "session-1",
  "content": {
    "subject": "user",
    "predicate": "reported",
    "object": "phishing email"
  },
  "provenance": {
    "source": "user_message",
    "ingestion_method": "direct_write",
    "trust_tier": "agent_derived"
  },
  "scope": "session_shared"
}
```

**Episodic event**

```json
{
  "type": "episodic",
  "agent_id": "agent-1",
  "session_id": "session-1",
  "content": {
    "summary": "User reported phishing email"
  },
  "provenance": {
    "source": "user_message",
    "ingestion_method": "direct_write",
    "trust_tier": "agent_derived"
  },
  "scope": "agent_private"
}
```

**Working memory**

```json
{
  "type": "working",
  "agent_id": "agent-1",
  "session_id": "session-1",
  "content": {
    "active_task": "investigate phishing report"
  },
  "provenance": {
    "source": "agent_inference",
    "ingestion_method": "direct_write",
    "trust_tier": "agent_derived"
  },
  "scope": "session_shared"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `type` | yes | `semantic`, `episodic`, or `working` |
| `agent_id` | yes | Caller identity |
| `session_id` | no | Required for episodic/working and session_shared semantic |
| `content` | yes | Type-dependent content map |
| `provenance` | yes | Object with `source`, `ingestion_method`, `trust_tier` |
| `scope` | yes | `agent_private`, `session_shared`, or `org_shared` |

### Response `200`

```json
{"status": "written", "id": "..."}
```

Other possible statuses: `"quarantined"`, `"duplicate"`.

### Response `400`

```json
{"error": "embedding_failed"}
```

Returned when the embedding service is unavailable and the fact cannot be stored with a vector. Semantic and episodic writes require a valid embedding.

### Curl

```bash
curl -X POST http://localhost:4000/memory/write \
  -H "Authorization: Bearer $JIYI_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "semantic",
    "agent_id": "agent-1",
    "session_id": "session-1",
    "content": {"subject": "user", "predicate": "reported", "object": "phishing email"},
    "provenance": {"source": "user_message", "ingestion_method": "direct_write", "trust_tier": "agent_derived"},
    "scope": "session_shared"
  }'
```

---

## `POST /auth/mcp-token`

Issue a short-lived MCP session token for an agent.

### Headers

```text
Authorization: Bearer <token>
Content-Type: application/json
```

### Request body

```json
{
  "agent_id": "agent-1",
  "org_id": "org-1"
}
```

### Response `200`

```json
{
  "token": "tok_...",
  "expires_in": 300
}
```

### Curl

```bash
curl -X POST http://localhost:4000/auth/mcp-token \
  -H "Authorization: Bearer $JIYI_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "agent-1"}'
```

---

## `POST /admin/agents`

Create a per-agent API key. Requires admin token.

### Headers

```text
Authorization: Bearer <admin-token>
Content-Type: application/json
```

### Request body

```json
{
  "agent_id": "agent-1",
  "org_id": "org-1"
}
```

### Response `201`

```json
{
  "agent_id": "agent-1",
  "api_key": "key_..."
}
```

### Curl

```bash
curl -X POST http://localhost:4000/admin/agents \
  -H "Authorization: Bearer $JIYI_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "agent-1"}'
```

---

## `GET /admin/quarantine`

List pending quarantine entries. Requires admin token.

### Headers

```text
Authorization: Bearer <admin-token>
```

### Response `200`

```json
{
  "entries": [
    {
      "id": "...",
      "target_table": "episodic_events",
      "reason": "compositional_anomaly",
      "created_at": "2026-06-23T08:30:00.000000Z",
      "payload": { "summary": "..." }
    }
  ]
}
```

### Curl

```bash
curl http://localhost:4000/admin/quarantine \
  -H "Authorization: Bearer $JIYI_API_TOKEN"
```

---

## `POST /admin/quarantine/:id/promote`

Promote a pending quarantine entry back into the live memory table. Requires admin token.

### Headers

```text
Authorization: Bearer <admin-token>
```

### Response `200`

```json
{"status": "promoted", "id": "..."}
```

### Response `409`

```json
{"error": "already_reviewed"}
```

### Curl

```bash
curl -X POST "http://localhost:4000/admin/quarantine/$ENTRY_ID/promote" \
  -H "Authorization: Bearer $JIYI_API_TOKEN"
```

---

## `POST /admin/quarantine/:id/reject`

Reject a pending quarantine entry. Requires admin token.

### Headers

```text
Authorization: Bearer <admin-token>
```

### Response `200`

```json
{"status": "rejected", "id": "..."}
```

### Response `404`

```json
{"error": "not_found"}
```

### Response `409`

```json
{"error": "already_reviewed"}
```

### Curl

```bash
curl -X POST "http://localhost:4000/admin/quarantine/$ENTRY_ID/reject" \
  -H "Authorization: Bearer $JIYI_API_TOKEN"
```

---

## `POST /embed` (local embedding server)

When `JIYI_EMBEDDING_SERVER_ENABLED=true`, Jiyi starts a bundled embedding server on `JIYI_EMBEDDING_SERVER_PORT` (default `8001`). It requires no authentication.

### Request

```http
POST /embed
Content-Type: application/json

{"text": "user reported phishing email"}
```

### Response `200`

```json
{"embedding": [0.012, -0.034, ..., 0.019]}
```

The vector has 768 dimensions to match the Postgres `vector(768)` columns. Set `JIYI_EMBEDDING_ENDPOINT=http://localhost:8001/embed` so Jiyi's circuit breaker uses this server.

### Curl

```bash
curl -X POST http://localhost:8001/embed \
  -H "Content-Type: application/json" \
  -d '{"text": "user reported phishing email"}'
```

---

## `POST /mcp`

MCP streamable HTTP endpoint. **No `Authorization` header is required**; each tool authenticates via its `session_token` argument.

Enabled when `JIYI_MCP_TRANSPORT=streamable_http`. Point an MCP client at `http://localhost:4000/mcp`.

### Tools

- `context_assemble`
- `memory_write`

### Example: call `context_assemble` via curl

```bash
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "context_assemble",
      "arguments": {
        "agent_id": "agent-1",
        "session_id": "session-1",
        "session_token": "tok_...",
        "task": "What do we know about the phishing report?"
      }
    },
    "id": 1
  }'
```

For `stdio` transport, spawn the server process directly instead of using `/mcp`:

```bash
JIYI_MCP_TRANSPORT=stdio mix run --no-halt
```

---

## Status codes

| Code | Meaning |
|------|---------|
| `200` | Success |
| `201` | Created (admin/agents) |
| `400` | Bad request / validation error |
| `401` | Missing or invalid bearer token |
| `403` | Bearer token does not permit this action (e.g. admin required or agent_id mismatch) |
| `404` | Resource not found |
| `409` | Conflict (e.g. quarantine entry already reviewed) |
