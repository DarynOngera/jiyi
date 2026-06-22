# Jiyi Implementation Tasks

Tracked phases from the design and implementation spec.

## Phase 1 – Skeleton & Supervision Tree
- [x] Create Mix project (`mix new jiyi --sup`)
- [x] Add dependencies: Bandit, Plug, Ecto SQL, Postgrex, pgvector, hermes_mcp, telemetry, Jason, Finch
- [x] Configure `config/config.exs`, `dev.exs`, `test.exs`, `runtime.exs`
- [x] Create Ecto repo with `Pgvector` types (`lib/jiyi/postgrex_types.ex`)
- [x] Generate migrations: `vector` extension, `session_checkpoints`, `episodic_events`, `semantic_facts`, `quarantine_entries`
- [x] Build supervision tree in `lib/jiyi/application.ex` exactly per spec §2
- [x] Crash-injection test confirming isolated subtree restart

## Phase 2 – Session Durability
- [x] Implement `Jiyi.Memory.SessionSupervisor` (DynamicSupervisor)
- [x] Implement `Jiyi.Memory.SessionState` with timer + write-count checkpointing
- [x] Rehydration test: kill session process, assert working memory is restored

## Phase 3 – Durable Memory Writes
- [x] Implement `Jiyi.Memory.EpisodicStore`
- [x] Implement `Jiyi.Memory.SemanticStore`
- [x] Implement `Jiyi.Memory.Quarantine`
- [x] Content-hash deduplication
- [x] External-untrusted routing to quarantine
- [x] Dedup and quarantine tests

## Phase 4 – Retrieval Pipeline
- [x] Implement `Jiyi.Retrieval` (route → fan-out → rank → compress → format)
- [x] Implement `Jiyi.Retrieval.Supervisor` with `Task.Supervisor`
- [x] Graceful degradation when a store is unavailable
- [x] Token-budget compression

## Phase 5 – API Boundary
- [x] Implement `Jiyi.API.Router` (`/context/assemble`, `/memory/write`)
- [x] Implement `Jiyi.API.MCPServer` with `context_assemble` and `memory_write` tools
- [x] Bearer-token auth
- [x] HTTP/MCP parity

## Phase 6 – Quality & Hardening
- [x] Telemetry events (`[:jiyi, :memory, :write]`, `[:jiyi, :memory, :read]`, etc.)
- [x] `Jiyi.EmbeddingClient.CircuitBreaker`
- [x] `Jiyi.Anomaly.Watcher` scanning for instruction-like phrasing
- [x] Retrieval eval fixture tests

## Remaining Environment Step
- [ ] Configure Postgres credentials and run `mix ecto.create && mix ecto.migrate`

## Phase 7 – Phase 2 Hardening & MCP Abstraction
- [x] Fix reference-vector cache (GenServer, Jiyi.Anomaly.ReferenceStore)
- [x] Fix isolate_offenders O(N²) embedding calls
- [x] Make quarantine_offender transactional (hold_and_delete/4)
- [x] Register [:jiyi, :retrieval, :compositional_anomaly] telemetry event
- [x] Admin HTTP surface for quarantine review
- [x] Extract Jiyi.MCP.Tools (shared tool logic)
- [x] Client-side MCP adapter behaviour + AnubisAdapter
- [x] Server-side mcp_server_module config
- [x] Provider extension documentation in README
