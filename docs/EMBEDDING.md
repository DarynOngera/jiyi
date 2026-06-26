# Embeddings in Jiyi

An embedding is a dense numerical vector that represents the meaning of a
piece of text. Two pieces of text that mean similar things will have vectors
that point in similar directions in high-dimensional space, even if they share
no words. Jiyi uses embeddings to enable semantic similarity search — finding
memories that are conceptually relevant to a query even when the exact words
do not match.

---

## What embeddings are in Jiyi's context

Jiyi does not run an embedding model itself. It calls an external HTTP
endpoint — configured via the `JIYI_EMBEDDING_ENDPOINT` environment variable
(default: `http://localhost:8000/embed`) — and expects back a JSON array of
floating-point numbers representing the vector for the input text.

The dimensionality of this vector is configurable at setup time via
`config/config.exs`. The default is 768 dimensions, which is typical for
models like `nomic-embed-text`, `all-MiniLM-L6-v2`, and similar sentence
transformers. The dimension must be chosen before running the first database
migration because it determines the column size in the vector index and cannot
be changed without recreating the index.

The actual model used is entirely the operator's choice. Jiyi makes no
assumptions about model architecture. The only contract is that the endpoint
accepts a JSON body with a `text` field and returns either a top-level JSON
array of numbers or a JSON object with an `embedding` key containing that
array.

---

## When embeddings are computed

Embeddings are computed **at write time**, not at retrieval time.

When an episodic event or semantic fact is written, Jiyi extracts the
relevant text from the record — the `summary` field for episodic events, and
the concatenation of `subject`, `predicate`, and `object` for semantic facts
— and sends it to the embedding endpoint before inserting the row into the
database. If the embedding is returned successfully, it is stored alongside
the record. If the embedding call fails for any reason, the write proceeds
without a vector and the row is inserted with a null embedding column.

This means embedding availability is best-effort and non-blocking. A memory
will be stored and retrievable via full-text search even if it has no
embedding. It simply will not participate in vector similarity queries.

Working memory and procedural memory do not receive embeddings. Working memory
is transient key-value state. Procedural memory is read from files at assembly
time and is never stored in the database.

---

## How embeddings are stored

Embeddings are stored in PostgreSQL using the `pgvector` extension, which adds
a native `vector` column type to Postgres. The `episodic_events` table has an
`embedding vector(768)` column (or whatever dimension was configured), and the
`semantic_facts` table has the same.

Each table has an HNSW index (Hierarchical Navigable Small World) on its
embedding column using L2 (Euclidean) distance. HNSW is an approximate nearest
neighbour algorithm — it trades a small amount of recall accuracy for very
fast query times even at large dataset sizes.

The Elixir side uses the `pgvector` hex package to handle serialisation and
deserialisation of vector values between Elixir lists and the Postgres binary
format. The `Pgvector.Ecto.Vector` type is used in the schema so Ecto can
cast and query these columns natively.

---

## How embeddings are used in retrieval

In the retrieval fan-out, both the episodic and semantic store queries accept
an optional `:embedding` filter. When an embedding is provided, the query
adds an `ORDER BY embedding <-> $vector` clause, which uses the HNSW index to
order results by L2 distance from the query vector. Closer vectors appear
first.

In the current default retrieval path, the embedding filter is not used for
the primary fan-out queries. Full-text search (`ts_rank` and
`plainto_tsquery`) is used instead. The embedding ordering clause exists in
the store query interfaces and can be activated by callers who pass an
embedding opt, but the default `Jiyi.Retrieval.assemble` pipeline currently
relies on FTS relevance for ranking rather than vector similarity.

This is intentional for the initial implementation — FTS is cheaper (no
embedding call at query time) and more predictable. Vector similarity ranking
is available as an extension point once the operator has profiled whether it
improves recall for their specific use case.

---

## The circuit breaker

The embedding endpoint call is wrapped in a circuit breaker GenServer
(`Jiyi.EmbeddingClient.CircuitBreaker`). The circuit breaker exists because
the embedding service is an external dependency that may be slow, flaky, or
temporarily unavailable, and a slow embedding call would otherwise block every
memory write in the system.

The circuit breaker operates in three states:

**Closed (normal operation).** Embedding calls are forwarded to the endpoint.
If a call fails, the failure counter increments. Once the failure count reaches
the configured threshold, the circuit opens.

**Open (failure mode).** No embedding calls are made. Any request for an
embedding immediately returns an error. After a configured cooldown period, the
circuit transitions to half-open to probe whether the endpoint has recovered.

**Half-open (recovery probe).** A single test embedding call is made. If it
succeeds, the circuit closes and normal operation resumes. If it fails, the
circuit re-opens and the cooldown period resets.

When the circuit is open, memory writes proceed without embeddings. Retrieved
memories from that period will have null embedding columns but are otherwise
fully functional. The circuit breaker emits a telemetry event on every state
transition so operators can observe embedding endpoint health in their
monitoring system.

---

## Embeddings in anomaly detection

Embeddings serve a second role in Jiyi beyond retrieval: they power one of the
three signals in the anomaly detector.

The anomaly detector maintains a list of reference vectors representing known
prompt-injection phrases. These vectors are loaded at startup by the
`ReferenceStore` GenServer, which calls the embedding endpoint for each phrase
in the `anomaly_reference_injections` config list and caches the results in
process state.

When the detector evaluates a piece of text, it optionally accepts a
pre-computed embedding vector for that text. If provided, the detector
computes the cosine similarity between the input vector and each reference
vector, and uses the maximum similarity as an embedding-distance signal in the
composite anomaly score. If no vector is provided and the embedding weight is
non-zero, the detector calls the circuit breaker to fetch an embedding on
demand.

This signal is most valuable for catching injection phrasing that is
semantically similar to known patterns but uses different words — paraphrases,
euphemisms, or non-English variants that would not match the keyword list.

Cosine similarity is used rather than L2 distance for this comparison because
it is scale-invariant: it measures the angle between vectors rather than their
absolute distance, which makes it more robust when comparing embeddings of
texts of different lengths.

---

## Operational considerations

**Model consistency.** The embedding model must remain consistent across the
lifetime of the stored vectors. If you switch to a different model, previously
stored embeddings are no longer comparable to new ones. A full re-embedding of
existing records is required when changing models, which means re-inserting all
rows with updated vectors. There is no built-in migration path for this.

**Dimension lock-in.** The vector dimension is baked into the database schema
at migration time. Changing it requires dropping and recreating the embedding
columns and their HNSW indexes.

**Null embeddings are silent.** There is no record of which rows have null
embeddings due to endpoint failures. If you need to backfill embeddings for
records written during an outage, you must query for rows where the embedding
column is null and re-embed them.

**Reference vector staleness.** The `ReferenceStore` loads reference vectors
once at startup. If you update the `anomaly_reference_injections` config at
runtime, call `Jiyi.Anomaly.ReferenceStore.reload()` to refresh the cache.
The old vectors remain active until reload completes.
