# Ranking Matrix in Jiyi

After retrieval fans out across episodic, semantic, working, and procedural
memory sources, all results are merged into a single list and sorted by a
composite score. This score determines which memories the agent sees first and
which are dropped when the token budget is exhausted. Understanding the ranking
matrix is essential for reasoning about why a particular memory appears or does
not appear in assembled context.

---

## The formula

Every memory item receives a score calculated as:

```
score = base_score × recency_multiplier × relevance_multiplier
```

All three components are non-negative real numbers. The final score is also
non-negative. Items are sorted in descending order — highest score first. The
token budget is consumed in this order, so the top-ranked item is always
included before any lower-ranked item is considered.

---

## Base score

The base score reflects how trustworthy the source of the memory is. It is
derived from the item's `trust_tier` for database-backed memories, or from
the item's type for in-memory items.

### Trust tier weights (episodic and semantic memories)

| Trust tier | Default weight |
|---|---|
| `human_asserted` | 1.0 |
| `agent_derived` | 0.7 |
| `external_untrusted` | 0.3 |

`human_asserted` is the highest weight because the claim was explicitly
verified at the credential layer — only the shared admin token can write this
tier. `agent_derived` is the default for inferences made by the agent itself.
`external_untrusted` is the lowest because the content came from outside the
controlled environment and was stored for observability rather than reliability.

In practice, `external_untrusted` memories are quarantined at write time and
rarely appear in the live tables. If one does appear — for example, if the
anomaly detector did not flag it — it will be ranked last among all
database-backed items.

### Type weights (working and procedural memory)

Working memory and procedural memory do not have a `trust_tier` field. They
use fixed type weights:

| Memory type | Default weight |
|---|---|
| Working memory | 0.95 |
| Procedural memory | 0.85 |

Working memory is pinned very high because it represents the agent's live,
current-session state — information that is directly relevant to what the agent
is doing right now. It is almost always more relevant than any historical
episodic or semantic fact.

Procedural memory is pinned slightly below working memory because playbooks are
general-purpose instructions rather than session-specific observations. They
provide valuable scaffolding but should not completely crowd out contextual
memories.

Both type weights are configurable. Setting working memory weight below the
trust tier weights for episodic memories would cause historical facts to
outrank current session state, which is rarely desirable.

### Fallback

If an item has no recognisable trust tier and is not a known in-memory type,
it receives a base score of 0.5. This acts as a neutral midpoint and prevents
unknown items from being sorted to the extremes.

---

## Recency multiplier

The recency multiplier decays exponentially with the age of the memory. A
freshly written memory scores close to 1.0. An old memory scores much lower.

The decay formula is:

```
recency = max(floor, 0.5 ^ (age_hours / half_life))
```

The default parameters are:
- **Half-life**: 8 hours. A memory that is 8 hours old scores 0.5 of its
  initial recency value. A memory 16 hours old scores 0.25, and so on.
- **Floor**: 0.1. No memory's recency multiplier ever drops below 0.1,
  regardless of age. This ensures very old but highly trusted memories are
  never completely excluded from competition — they simply rank low.

Both the half-life and the floor are configurable, allowing operators to tune
how aggressively the system favours recent information. A shorter half-life
makes the system more present-biased; a longer half-life gives historical
memories more staying power.

### Which timestamp is used

- **Episodic memories** use `occurred_at` — the time the event happened,
  not the time it was written. This means an episodic event that is written
  with a backdated `occurred_at` will score as if it is old.

- **Semantic facts** use `valid_from` — the time from which the fact became
  valid. A semantic fact that is updated (written with a fresh `valid_from`)
  will score as fresh even if an older version of the same fact exists
  elsewhere.

- **Working memory** and **procedural memory** have no timestamps. They
  receive a recency multiplier of 1.0 — they are always treated as maximally
  fresh. This is correct for working memory (which is live session state) and
  acceptable for procedural memory (which is version-controlled and replaced
  wholesale rather than aged).

---

## Relevance multiplier

The relevance multiplier reflects how closely a memory matches the task query
that triggered retrieval. It comes from PostgreSQL's full-text search ranking
function, `ts_rank`.

When a store query includes a text search filter — which is always the case in
the default `context_assemble` pipeline — the query returns a `relevance`
float alongside each row. This is the `ts_rank` score computed by Postgres
over the indexed text columns for that row against the query terms.

### Behaviour

- A memory that contains many of the query terms, especially in high-density
  positions (shorter documents score higher per matching term), receives a
  high `ts_rank` value.
- A memory with no matching terms would not appear in the results at all
  because the FTS filter excludes it before ranking.
- The `ts_rank` scale is not normalised to a fixed range. Scores are relative
  to each other within a result set, not absolute.

A relevance multiplier of 0.0 would eliminate an item regardless of its base
score and recency. To prevent this, the system applies a floor of 0.1 to the
relevance multiplier when the `ts_rank` value is positive. If no relevance
value is available — which happens for working memory, procedural memory, and
any item retrieved outside the FTS path — the multiplier defaults to 1.0,
meaning relevance is neutral and does not adjust the score.

---

## How the components interact

The three multipliers interact in ways that are important to understand when
debugging why a particular memory ranked where it did.

**A high-trust old memory competes poorly against a low-trust fresh memory.**
A `human_asserted` memory written a week ago scores:
`1.0 × 0.5^(168/8) × relevance = 1.0 × ~0.0005 × relevance`.
An `agent_derived` memory written an hour ago scores:
`0.7 × ~0.99 × relevance = ~0.69 × relevance`.
The fresh agent-derived memory almost always wins. This is intentional — the
system is biased toward recent information on the assumption that stale facts,
even from authoritative sources, are less useful than fresh context.

**Working memory almost always ranks above episodic and semantic memories.**
With a base score of 0.95 and a recency multiplier of 1.0, working memory
needs a relevance score above approximately 0.75 from a `human_asserted` item
with a recency multiplier above 0.85 to be outranked. In practice, current
session state from working memory nearly always surfaces at or near the top
of assembled context.

**Procedural memory ranks above most episodic and semantic content but below
working memory.** With a base of 0.85 and a recency of 1.0, procedural items
score 0.85 before relevance adjustment. A highly relevant `human_asserted`
recent episodic event (score near 1.0) will outrank procedural content, but
typical `agent_derived` episodic memories will not.

**Relevance is a filter amplifier, not a ceiling.** Because items with no FTS
match are excluded entirely by the store query, the relevance multiplier only
applies to items that already passed a relevance threshold. It then
differentiates between equally-relevant items by how closely they match the
query terms. Two items with the same trust tier and age but different relevance
scores will rank in order of relevance.

---

## Configuring the weights

All default weights are overridable without code changes. The following
application config keys control the ranking behaviour:

| Config key | Controls |
|---|---|
| `:retrieval_trust_tier_weights` | Map of trust tier strings to float weights |
| `:retrieval_type_weights` | Map of `:working` and `:procedural` atoms to float weights |
| `:retrieval_recency_half_life_hours` | Recency decay half-life in hours |
| `:retrieval_min_recency_multiplier` | Recency floor value |

These can be set in `config/runtime.exs` and will take effect without
recompilation. The relevance multiplier is not configurable because it comes
directly from Postgres's `ts_rank` function and cannot be scaled independently
without modifying the query.

---

## What ranking does not do

Ranking in Jiyi does not filter by trust tier — low-trust items are not
excluded, they are simply ranked lower. An `agent_derived` memory can outrank
a `human_asserted` one if it is fresh enough and the old one is stale.

Ranking does not de-duplicate. If the same fact appears as both an episodic
event and a semantic fact, both will be ranked and both may appear in the
assembled context. Callers that want deduplication should inspect the `sources`
list and post-process the context if necessary.

Ranking does not account for recency of access — only recency of creation or
validity. A memory that was accessed many times is not boosted over one that
was never accessed but was written more recently.
