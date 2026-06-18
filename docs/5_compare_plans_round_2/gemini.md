I strongly recommend **sticking entirely with Postgres and Oban**, actively
resisting the urge to introduce a dedicated message broker (like Kafka,
RabbitMQ, or Redis) until you hit a mathematically proven wall.

Here is my detailed rationale for keeping the orchestration tightly bound to
Postgres, along with a strategy for handling the high-throughput effects without
melting your database.

### 1. The Power of the Single Transactional Boundary

The entire philosophy of your Phase 1.5/2 plan revolves around immutable
evidence, strictly enforced gates, and verifiable `RunAttempts`.

If you use Oban with Postgres, your business logic and your job queue share the
same ACID transactional boundary. When a `StationRun` completes and updates a
`ContractLock`, the Oban job that triggers the next step is enqueued in the
exact same database transaction. If the transaction rolls back, the job never
fires. If you introduce an external message broker, you suddenly inherit the
"dual-write problem" and have to build complex distributed sagas or outbox
patterns just to guarantee state consistency.

### 2. Protecting the Self-Contained Distribution Model

Introducing an external broker immediately bloats the infrastructure
requirements. Keeping the architecture limited to the application binary and
Postgres preserves a clean, easily distributable, local-first ownership model.
Operators can spin the whole system up locally or on a single robust machine
without needing to manage a Kafka cluster or a Redis instance. It keeps the
operational surface area aggressively small.

### 3. Leveraging OTP for Transient "Broker" Needs

You are building in Elixir/OTP, which means you already have a world-class,
distributed message broker built directly into the VM.

- For **durable, guaranteed execution** (like compiling the graph or kicking off
  the Test Architect), use Oban/Postgres.
- For **high-throughput, transient fire-and-forget effects** (like streaming
  agent tokens to a UI, emitting telemetry, or broadcasting real-time progress),
  use `Phoenix.PubSub` or standard OTP messaging. You don't need Redis or
  RabbitMQ for transient pub/sub when the BEAM does it natively in memory.

### 4. Handling High-Throughput Artifacts (The "Escape Hatch")

The main risk of a Postgres-only Oban setup is bloating the database with
massive JSON payloads (like raw stochastic event streams, full context packs, or
deep agent trace logs).

Instead of moving orchestration to a message broker, change where the payloads
live:

- **The Oban payload should only contain pointers.** Pass lightweight IDs and
  content-digests in the job arguments.
- **Offload the heavy artifacts to Serverless Object Storage.** Have the worker
  write the raw, high-volume event streams or context maps directly to an object
  store (like S3 or R2).
- **Analyze offline.** Because everything is content-addressed and stored as raw
  files/blobs, you can query those artifacts entirely offline using an embedded
  analytical engine like DuckDB, completely bypassing Postgres for heavy
  read/analytical workloads.

By keeping Postgres focused strictly on state transitions and Oban job pointers,
a well-tuned Postgres instance can easily handle tens of thousands of jobs per
second—far exceeding the throughput requirements of a sequential AI agent
execution loop.

---

Given that Oban jobs will be handling the heavy lifting of state transitions in
the background, how are you planning to stream those real-time execution updates
and station effects back to the operator in the Qualification Cockpit and Plan
Workbench?

If I were architecting the real-time telemetry and UI streaming for this system,
I would treat the problem strictly as a separation of **state** (which belongs
in Postgres) and **exhaust** (which belongs in memory and object storage).

If you route high-frequency LLM tokens, trace events, and agent scratchpad logs
through an ACID database, you will exhaust your transaction pool and bloat the
database with write-ahead-log (WAL) churn.

Here is exactly how I would design the real-time stream for the Qualification
Cockpit and Plan Workbench, leveraging the native strengths of the BEAM (Erlang
VM) and serverless storage, completely bypassing Postgres for the heavy traffic.

### 1. The Real-Time Broadcast (Phoenix.PubSub)

Because you are in the Elixir/OTP ecosystem, you have a native, distributed
message broker built directly into the runtime.

When a worker picks up a `StationRun` to execute a stochastic agent loop, it
does not write token streams to the database. Instead, it emits events directly
to a `Phoenix.PubSub` topic—for example, `attempt:stream:BAT-BUGFIX-001`.

- **The mechanism:** The agent runner pushes lightweight tuples (e.g.,
  `{:token, "const"}`, `{:tool_start, "grep"}`) onto the in-memory bus.
- **The benefit:** This costs zero network hops and zero disk I/O. It is purely
  in-memory process messaging.

### 2. The Workbench Consumption (Phoenix LiveView)

The operator's browser does not poll an API. The LiveView process running on the
server subscribes to the `attempt:stream:BAT-BUGFIX-001` topic.

- As the agent runner broadcasts tokens and tool events, the LiveView receives
  them and updates its socket state.
- The DOM updates seamlessly via WebSockets. The operator watches the agent
  "type" its proposal and invoke tools in real time.
- **Database hit:** 0 queries.

### 3. The Durability Layer (ETS to R2/S3)

While the UI is consuming the stream in real time, you still need to preserve
this exhaust to seal the immutable `AgentCassette` for future replays or offline
DuckDB analysis.

Instead of writing to Postgres, the worker process implements a buffering
strategy:

- **Buffer:** The worker routes the raw event stream into an in-memory ETS
  (Erlang Term Storage) table or a lightweight GenServer buffer.
- **Flush:** Every _N_ seconds or _M_ kilobytes, the buffer flushes a `.jsonl`
  (JSON Lines) chunk directly to an S3-compatible object store like Cloudflare
  R2.
- **Commit:** When the `StationRun` completes, the buffer flushes its final
  chunk. Only then does the worker make a **single transaction** to Postgres,
  updating the `RunAttempt` status to `completed` and saving the R2 URI
  (`r2://conveyor-cassettes/bat-bugfix-001/events.jsonl`).

### 4. The Reconciliation Strategy (The "Catch-Up")

If the operator refreshes their browser mid-run, they need to see what happened
before they connected.

- The LiveView mounts, reads the Postgres `RunAttempt` to find the R2 bucket
  prefix, and fetches the durable chunks written so far.
- It simultaneously checks the active worker's ETS buffer for the "hot" events
  that haven't been flushed yet.
- It stitches the cold storage and hot buffer together, rendering the complete
  timeline, and then begins listening to the PubSub topic for new events.

---

This architecture keeps Postgres fiercely protective of your canonical work
graph, constraints, and state transitions, while utilizing R2 for
high-throughput immutable logs and OTP for real-time observability.

If you were to implement this buffer-and-flush pattern, how aggressive would you
set the retention policy on those raw `.jsonl` exhaust files before they are
either compressed or aged out to colder storage?

Because you are architecting a system where the operator owns the infrastructure
and the artifacts, you don't have to build a monolithic, infinite-retention SaaS
trap. You can be highly aggressive with noise while permanently preserving
signal.

The strategy should be driven by the economics of zero-egress object storage and
the ability to query compressed data in place. Exhaust data is not created
equal: a successfully completed `AgentCassette` is a high-value asset for future
evaluation or fine-tuning, while a run that failed due to a malformed AST
extraction is useless noise after a week.

Here is the retention and pruning strategy I would implement:

## 1. The Triaged Lifecycle

Instead of a blanket time-to-live (TTL) on the bucket, split the lifecycle into
three distinct phases based on how the Evidence Time Machine and operator will
interact with the data.

| Phase       | Timeframe  | Format          | Purpose                                            |
| ----------- | ---------- | --------------- | -------------------------------------------------- |
| **Hot**     | 0-14 Days  | Raw `.jsonl`    | Immediate triage, UI replay, Evidence Time Machine |
| **Cold**    | 15-90 Days | Zstd `.parquet` | Offline analytical queries, macro-trend reporting  |
| **Archive** | 90+ Days   | Pruned subset   | Golden master corpus for future model fine-tuning  |

---

## 2. Phase Details & Mechanisms

### The "Hot" Forensics Window (0-14 Days)

Keep the raw `.jsonl` files exactly as the worker flushed them.

- **Why:** If an operator needs to load up the Workbench to figure out why an
  execution failed yesterday, the system needs to pull those files instantly
  without decompression overhead.
- **Action:** 14 days is plenty of time for active debugging. If a failed run
  hasn't been investigated in two weeks, it never will be.

### The "Cold" Analytical Window (15-90 Days)

Run a background Oban cron job that sweeps `completed` and `failed` runs older
than 14 days. It downloads the `.jsonl` chunks, converts them into heavily
compressed `.parquet` files (using Zstandard compression), uploads the Parquet
files back to storage, and deletes the raw JSON lines.

- **Why:** Parquet is columnar. By structuring the schema to index on `run_id`,
  `station_key`, and `token_type`, you shrink the storage footprint by 80-90%.
- **The Kicker:** Analytical engines like DuckDB can query Parquet files
  directly over the network via HTTP range requests. Because object stores like
  R2 don't charge for egress, your local CLI or analytical dashboard can run
  complex `GROUP BY` queries across gigabytes of historical agent exhaust
  without downloading the whole dataset and without paying a dime in bandwidth.

### The Pruning Fork (90+ Days)

At the 90-day mark, the system gets aggressive and splits the data based on the
run's final classification:

1. **Delete the Noise:** Purge any Parquet files associated with
   `implementation_bug`, `infra_failure`, `context_miss`, or `flaky_test`. They
   have outlived their analytical usefulness and are just eating storage.
2. **Preserve the "Golden Master":** Keep the exhaust from clean, first-pass
   successes, as well as highly rated Contract Critic reviews and explicitly
   human-approved edge cases.

- **Why:** You are building a curated, high-quality dataset of agent
  interactions. If you eventually decide to fine-tune a local 8B or 14B
  parameter model to act as a dedicated Conveyor Decomposer or Test Architect,
  you will need thousands of perfect examples. This archive _becomes_ your
  fine-tuning corpus.

To maximize DuckDB’s analytical performance over remote object storage (like S3
or R2), the layout must be optimized for **projection pushdown** (reading only
specific columns) and **predicate pushdown** (skipping files and row groups
entirely without downloading them).

Because object storage penalties are driven by HTTP GET request latencies rather
than bandwidth, the golden rule is to avoid creating millions of tiny files
while keeping row-group statistics incredibly tight.

---

## 1. The Partitioning Strategy (Directory Layout)

Avoid over-partitioning. Partitioning by high-cardinality keys like `run_id` or
exact `date` creates a massive tree of tiny files, destroying DuckDB's
performance. Instead, use a coarse Hive-partitioning scheme combined with
internal file sorting.

```text
r2://conveyor-cassettes/year=YYYY/month=MM/

```

### Why this boundary?

- **Prevents the Small File Problem:** Keeps individual Parquet files
  target-sized between **20MB and 100MB**.
- **Leverages Parquet Row Groups:** Instead of creating separate physical
  directories for every station, bake that multi-tenancy _inside_ the single
  Parquet file and rely on DuckDB to read only the blocks it needs.

---

## 2. The Secret Sauce: Internal Row Sorting

Before writing the Parquet file during the Phase 1.5 sweep, you must globally
sort the dataframe or dataset. This ensures that the min/max statistics for each
10,000-row "row group" inside the Parquet file do not overlap, enabling instant
predicate pushdown.

Sort the rows using the following compound key hierarchy:

1. **`station_key`** (Lowest cardinality, groups all identical agent steps
   together)
2. **`run_id`** (Clusters an entire individual execution trace sequentially)
3. **`sequence_number`** (Preserves time order within the run)

If DuckDB executes `WHERE station_key = 'TestArchitect' AND run_id = '...'`, it
uses the file metadata to skip 99% of the file's bytes, fetching only the exact
byte-range of the matching row group via HTTP range requests.

---

## 3. The Optimized Parquet Schema

DuckDB handles complex nested types (`STRUCT`, `LIST`) natively with zero
parsing overhead. Move away from raw JSON strings for structured metadata to
avoid on-the-fly string parsing during queries.

| Column Name       | Parquet Data Type                              | Optimization Role / Note                                                                                 |
| ----------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `sequence_number` | `INT64`                                        | Monotonically increasing counter for exact trace ordering.                                               |
| `timestamp`       | `TIMESTAMP`                                    | Microsecond precision for performance profiling.                                                         |
| `run_id`          | `UUID` or `BYTE_ARRAY`                         | Stored as fixed binary or compact string for indexing.                                                   |
| `attempt_id`      | `UUID` or `BYTE_ARRAY`                         | Differentiates retries within the same run.                                                              |
| `station_key`     | `DICTIONARY(VARCHAR)`                          | Dictionary encoding compresses repeated station names to near-zero bytes.                                |
| `event_type`      | `DICTIONARY(VARCHAR)`                          | E.g., `token`, `tool_call`, `tool_response`, `error`, `lifecycle`.                                       |
| `actor`           | `DICTIONARY(VARCHAR)`                          | E.g., `agent`, `system`, `user`, `critic`.                                                               |
| `content`         | `VARCHAR`                                      | The raw token or text content. Unsorted, highly compressible via Zstd.                                   |
| `metrics`         | `STRUCT(tokens INT32, cost duration_ms INT32)` | Fixed-schema execution metrics. DuckDB can query `metrics.duration_ms` without reading `metrics.tokens`. |
| `meta`            | `MAP(VARCHAR, VARCHAR)`                        | Flexible key-value store for arbitrary dynamic agent tags (e.g., model used, temperature).               |

---

## 4. How DuckDB Queries Exploit This Layout

With this layout implemented, look at how DuckDB executes common engineering and
analytical queries under the hood:

### Scenario A: Calculating Token Costs per Station

```sql
SELECT station_key, SUM(metrics.tokens)
FROM read_parquet('r2://conveyor-cassettes/year=2026/month=06/*.parquet')
GROUP BY station_key;

```

- **DuckDB Execution:** Thanks to projection pushdown, DuckDB completely ignores
  the massive `content` and `meta` columns. It downloads only the tiny
  byte-ranges representing the `station_key` and `metrics.tokens` columns across
  the files.

### Scenario B: Replaying a Specific Failed Run

```sql
SELECT sequence_number, actor, content
FROM read_parquet('r2://conveyor-cassettes/year=2026/month=06/*.parquet')
WHERE run_id = '018f3a2b-7cde-7123-bcde-facade123456'
ORDER BY sequence_number ASC;

```

- **DuckDB Execution:** DuckDB reads the footer metadata of the Parquet files
  first. Because the files are sorted internally by `station_key` and `run_id`,
  DuckDB identifies that the requested `run_id` exists in exactly one row group
  in a single file. It skips all other row groups, issuing a target HTTP GET
  request for just that slice of data.

is there anything else you would add to this plan or adjust are are you good
with how things stand now?

This architecture is now in a genuinely elite tier. By combining the strict
deterministic gating of the original plan with the high-performance, local-first
operational exhaust and network hygiene revisions we discussed, you have a
system that is built to survive the realities of stochastic AI generation.

I am completely confident in this plan as it stands. It is ready for
implementation.

However, to bridge the gap between a flawless architectural design and the messy
reality of production systems, there are exactly **three final
micro-adjustments** I would bolt onto the very edges of this plan before writing
the first line of code. They address the "unknown unknowns" of operating LLMs at
scale.

---

### 1. The Global "Runaway Train" Circuit Breaker

**The Gap:** The plan handles `budget_exhausted` gracefully per-run. But what
happens if a logic bug in the Work-Graph Compiler accidentally spins up 5,000
concurrent Oban jobs that all start slamming the Anthropic or OpenAI API,
bypassing per-run limits? **The Adjustment:** Introduce a hard, global circuit
breaker at the `AgentRunner` adapter level using Erlang's `:atomics` or a fast
ETS counter.

- Track a rolling window of total tokens or API spend across the entire
  node/cluster.
- If the global threshold (e.g., "$50 in 5 minutes" or "10M tokens per hour") is
  breached, the `AgentRunner` adapter hard-switches to `circuit_open` and
  instantly returns `{:error, :global_budget_exceeded}` without making network
  calls.
- This prevents a silent logic loop from bankrupting your API keys while you are
  asleep.

### 2. Deterministic Semantic Shedding (Context Overflow Policy)

**The Gap:** The `Planning Context Scout` gathers incredible data, and the
caching layer keeps it fast. But what happens when the exact required context
plus the `AgentBrief` equals 210,000 tokens, and your selected model's context
window is 200,000? **The Adjustment:** Do not let the external LLM API throw a
400 error and fail the station. Add a `Context Overflow Policy` to the
`RunSpec`.

- Assign priority weights to context items (e.g., `AgentBrief` = 100,
  `Locked Interfaces` = 90, `Likely Files` = 50, `Historical Exemplars` = 10).
- Run a fast, local tokenizer (like `tiktoken` via Rust NIF) right before the
  adapter fires.
- If it breaches the limit, deterministically shed the lowest-priority context
  items until it fits, and append a specific system warning to the prompt:
  _"SYSTEM NOTE: Context was truncated to fit limits. Historical exemplars were
  dropped."_ \* If it must drop critical context (priority > 80) to fit, _then_
  it fails deterministically before hitting the network.

### 3. Universal Trace ID Propagation

**The Gap:** You have state in Postgres, exhaust in R2, and real-time logs in
PubSub. When an Oban worker crashes due to an Elixir `MatchError`, you need to
instantly tie that BEAM crash back to the specific LLM output that caused it.
**The Adjustment:** Enforce a strict `trace_id` boundary.

- Generate a `trace_id` when the `PlanningRun` or `BatteryRun` starts.
- Inject it into the Oban job `args`.
- Inject it into `Logger.metadata([trace_id: trace_id])` so every BEAM log
  carries it.
- **Crucially:** Inject it into the HTTP headers sent to the LLM provider (e.g.,
  OpenAI/Anthropic support custom metadata headers). This allows you to
  cross-reference your internal failures with vendor-side API logs if you ever
  need to debug a provider-side degradation.

---

With those three guardrails securely in place, this blueprint is exceptionally
tight. The separation of concerns between deterministic state and stochastic
proposals is exactly how these systems must be built to scale safely.

Which of the Workstreams (A through F) are you planning to tackle first, and do
you want to start mapping out the initial data schemas for that specific
tranche?
