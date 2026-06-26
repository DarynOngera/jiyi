# Retrieval in Jiyi

Retrieval is the process by which Jiyi assembles a ranked, token-budgeted
slice of an agent's memory and returns it as a single context string ready
for injection into an LLM prompt. It is the read side of the memory system —
the counterpart to `memory_write`.

---

## What retrieval produces

A retrieval call returns three things:

- **`assembled_context`** — a single string of newline-separated memory items,
  prefixed by type tags such as `[episodic]`, `[semantic]`, `[working]`, and
  `[procedural]`. This string is intended to be placed directly into a system
  prompt or user turn.

- **`sources`** — a list of metadata records describing where each item came
  from: its type, its database ID or key, and its trust tier. Sources allow a
  caller to trace any item in the context back to its origin.

- **`token_count`** — an estimate of how many tokens the assembled context
  occupies, calculated as one token per four characters of English text. This
  is a heuristic, not an exact tokeniser count.

If an assembly-time anomaly is detected and cannot be isolated to specific
items, retrieval additionally returns `blocked: true` and an empty
`assembled_context`. In the normal case, `blocked` is always `false`.

---

## When retrieval fires

Retrieval is not automatic on every memory event. It fires at deliberate
points in the agent turn:

**Turn start.** Before the first LLM call in a turn, the harness calls
`context_assemble` with the user's task string. This is the primary retrieval
moment and always happens.

**Task shift.** If the current task differs significantly from the previous
turn's task — measured by word-token overlap — a second `context_assemble`
call fires with the new task before the LLM call. The two results are merged
and deduplicated by source ID.

**After a meaningful tool result.** When a `memory_write` call returns
`status: written`, the harness immediately runs a targeted `context_assemble`
using the written content as the task string. This surfaces related existing
memories that the new fact may be relevant to, before the follow-up LLM turn.

**Retrieval does not fire** when a write is quarantined (nothing new is in the
live store), when the task string is empty, or recursively inside a
`context_assemble` tool execution.

---

## The retrieval pipeline

Every call to `context_assemble` passes through five sequential stages.

### 1. Normalise

The request is normalised with defaults: a token budget of 4000 and all three
memory scopes (`agent_private`, `session_shared`, `org_shared`) if none are
specified by the caller.

### 2. Fan-out

Four concurrent retrieval tasks are spawned against independent sources. Each
task runs inside a supervised task pool with a shared 5-second timeout.

- **Episodic store** — queries `episodic_events` by full-text search over the
  `summary` field using the task string as the search query, filtered by the
  caller's scope context. Returns up to 10 results ordered by text relevance.

- **Semantic store** — queries `semantic_facts` by full-text search over the
  concatenated `subject`, `predicate`, and `object` fields. Returns only facts
  where `valid_until` is null (i.e. not yet invalidated). Returns up to 10
  results.

- **Working memory** — reads three fixed keys from the in-memory session
  state for the caller's `session_id`: `active_task`, `open_files`, and
  `recent_tool_outputs`. If no session is live for that `session_id`, returns
  nothing rather than failing.

- **Procedural memory** — matches the task string against a keyword map to
  identify a task type (e.g. "investigate", "incident", "deploy"), then reads
  all markdown playbook files for that task type from `priv/playbooks/`.

If any task exceeds the timeout or crashes, its result is silently dropped and
the other results proceed. This is the graceful degradation guarantee: a
crashed store never blocks context assembly.

### 3. Rank

All items from all four sources are merged into a single list and scored.
Each item receives a composite score:

```
score = base_score × recency_multiplier × relevance_multiplier
```

Items are sorted by this score in descending order. See the
[Ranking Matrix wiki](ranking-matrix.md) for a full description of how each
component is calculated.

### 4. Compress

Items are taken from the ranked list in order until adding the next item would
exceed the token budget. The budget is enforced in characters using the
1-token-per-4-characters heuristic. Items that would push over the budget are
dropped entirely — they are not truncated.

### 5. Format and anomaly check

The compressed items are formatted into the `assembled_context` string.
Procedural items are excluded from the anomaly scan because they are
operator-authored content, not agent or user input.

The remaining items are joined into a single string and passed through the
multi-signal anomaly detector. If the joined string is clean, the result is
returned immediately.

If the detector flags the joined string, Jiyi attempts to isolate the
offending item by re-scoring each candidate with one item held out at a time.
If an offender is identified, it is quarantined and removed from the DB, and
the clean remainder is returned to the caller. The caller does not see the
quarantined content and the next retrieval call will not include it.

If no single item can be isolated as the cause (the anomaly only emerges from
the combination), the entire `assembled_context` is blanked and `blocked:
true` is returned.

---

## Scope enforcement

Scope filtering happens at the database query level, not in application code
after retrieval. This means items that the caller is not authorised to see are
never loaded into memory in the first place.

The three scopes work as follows:

**`agent_private`** — an item is visible only to the agent whose `agent_id`
matches the item's stored `agent_id`. An agent cannot read another agent's
private memories even if they share a session.

**`session_shared`** — an item is visible to any caller whose `session_id`
matches the item's stored `session_id`. Any agent participating in the same
session can see session-shared memories regardless of `agent_id`.

**`org_shared`** — an item is visible to any caller whose `org_id` matches
the item's stored `org_id`. If no `org_id` is present on either the request
or the item, the item does not match this scope. A record written with
`org_shared` scope but without an `org_id` is permanently invisible under
org-shared queries.

The caller may request any combination of scopes. If all three are requested,
the DB query uses an OR condition across all three scope clauses simultaneously,
so items from different scopes are returned in a single efficient query per
store rather than three separate queries.

---

## Graceful degradation

Jiyi treats every store as potentially unavailable. The fan-out stage catches
any exit signal or exception from a store query and returns an empty list for
that source. A telemetry event is not emitted for the failure — the caller
receives a context assembled from whatever stores did respond.

This means a crashed `EpisodicStore` GenServer will cause episodic results to
be absent from retrieval, but semantic, working, and procedural memory will
still be returned normally. The caller cannot distinguish a crashed store from
an empty store based on the retrieval response alone.

---

## Retrieval and trust

Retrieval does not filter by trust tier. All items that pass scope checks are
candidates for inclusion. Trust tier affects **ranking** (higher trust scores
higher) but not eligibility. An `external_untrusted` item that somehow entered
the live tables would appear in retrieval results, just ranked low.

In practice, `external_untrusted` items are routed to quarantine at write time
and are never in the live tables. Items flagged by the anomaly detector at
write time are also quarantined before they can be retrieved. The anomaly check
at assembly time provides a second, compositional layer of defence.

---

## Token budget and compression

The default token budget is 4000 tokens. This can be overridden per request.

The budget is applied after ranking, which means the highest-ranked items are
taken first. A large item that would fit within the budget is always preferred
over multiple small items that together would exceed it.

There is no partial item inclusion. An item either fits within the remaining
budget and is included, or it does not and retrieval stops. This means the
actual token count in the result may be significantly below the budget if a
high-ranked item is large.

The token estimate in `token_count` reflects the assembled context only. It
does not account for the system prompt, conversation history, or tool
definitions that also consume tokens in the LLM call.
