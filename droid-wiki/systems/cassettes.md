# Cassettes

The cassette system in `lib/conveyor/cassettes.ex` and `lib/conveyor/cassettes/` records station runs for replay and freshness checks. A cassette captures the causal event stream, tool transcript, and primary outputs of one agent execution, sealed with redaction and integrity checks. The system separates generation freshness (what the agent was given) from evaluation surface (what the gate checked), so a cassette can be reused for hybrid replay when only the evaluation surface changed.

## Cassette builders

`lib/conveyor/cassettes.ex` provides artifact-shaped `CassetteSeries` and `AgentCassette` builders. A `CassetteSeries` is keyed by spec kind, spec digest, role, adapter, agent profile snapshot digest, capability snapshot digest, generation environment fingerprint digest, and generation freshness digest. Its id is content-addressed.

The `record/2` function builds an `AgentCassette` from a series and options. It requires integrity (series id and recording number), redacts primary outputs through `Security.Redactor`, and seals the cassette. If redaction is blocked, the cassette is rejected with `redaction_blocked` as the invalidation reason. Each cassette carries provider metadata (request id, model id, model revision, identity confidence), the agent event stream, tool transcript, primary output refs, patch set digest, retention class, and expiry.

## CausalTranscript

`lib/conveyor/cassettes/causal_transcript.ex` normalizes observable cassette event streams and tool records. Events are assigned monotonic per-stream sequence numbers, given stable `event_id` values (`<stream>:<sequence>`), and their `happens_after` references are preserved. Hidden keys (chain of thought, reasoning, private reasoning) are scrubbed from payloads. Tool records carry a tool contract key, tool call id, normalized args, policy decision, result, error, effect receipt ref, and caused-by reference, with an idempotency key derived from the record content.

## Freshness

`lib/conveyor/cassettes/freshness.ex` separates cassette generation and evaluation surfaces. Generation keys are prompt digest, role view digest, context pack digest, adapter profile digest, and tool contract digest. Evaluation keys are gate digest, verification digest, and obligation digest. The `classify/2` function compares a recorded cassette against the current surface:

- **`:fresh`** — both generation and evaluation surfaces match.
- **`:hybrid_replay_eligible`** — generation surface matches but evaluation surface changed.
- **`:generation_stale`** — generation surface changed; the cassette cannot be replayed.

## Nondeterminism

`lib/conveyor/cassettes/nondeterminism.ex` provides a deterministic virtual clock, id allocator, and nondeterminism ledger. The virtual clock advances from a fixed ISO-8601 start by ordinal index, so replay produces identical timestamps. The id allocator assigns monotonic ids per namespace. The ledger records clock reads, id allocations, env reads, external reads, and tool equivalence policies, so any nondeterministic input that affected a run is captured and reproducible.

## ReplayAnchorSet

`lib/conveyor/cassettes/replay_anchor_set.ex` selects representative replay anchors before an evaluated change. Anchors are chosen across four categories: successful, failed, disputed, and safety-sensitive. Each anchor carries its cassette ref, whether it is a valuable failure, and expected replay assertions. The anchor set is content-addressed with a selection policy digest.

## ReplayDiagnostics

`lib/conveyor/cassettes/replay_diagnostics.ex` produces structured diagnostics for strict replay divergence. It compares recorded and requested cassette content across three dimensions: causal sequence (event ids and happens-after references), tool contracts (tool call ids and contract keys), and normalized args. Divergence produces a finding with a rule key, anchor, severity, and next action (`record_new_cassette_or_fix_replay_request`).

## ReplayEngine

`lib/conveyor/cassettes/replay_engine.ex` makes mode-specific cassette replay decisions across four modes:

- **`:full`** — requires exact match of generation freshness, tool signatures, and event signatures. Produces `trust_gate_eligible?: true` with primary outputs.
- **`:hybrid`** — requires generation freshness match only. Reports whether the evaluation surface changed and includes gate results. Trust-gate eligible.
- **`:proposal`** — requires generation freshness match. Returns a proposal result. Trust-gate eligible.
- **`:compatible`** — compatibility-only mode. Not trust-gate eligible.

All modes require the current generation freshness digest to match the recorded one; otherwise the replay misses with `cassette_generation_stale`.

## Key source files

| File | Purpose |
| ---- | ---- |
| `lib/conveyor/cassettes.ex` | CassetteSeries and AgentCassette builders with redaction and sealing. |
| `lib/conveyor/cassettes/causal_transcript.ex` | Normalizes event streams and tool records with hidden-key scrubbing. |
| `lib/conveyor/cassettes/freshness.ex` | Separates generation and evaluation surfaces for freshness classification. |
| `lib/conveyor/cassettes/nondeterminism.ex` | Deterministic virtual clock, id allocator, and nondeterminism ledger. |
| `lib/conveyor/cassettes/replay_anchor_set.ex` | Selects representative replay anchors across four categories. |
| `lib/conveyor/cassettes/replay_diagnostics.ex` | Structured diagnostics for strict replay divergence. |
| `lib/conveyor/cassettes/replay_engine.ex` | Mode-specific cassette replay decisions (full, hybrid, proposal, compatible). |

## Related pages

- [Agent runner](agent-runner.md) — how agent events are recorded
- [Evidence recording](evidence-recording.md) — verification reruns and reproducibility
- [Gate](gate.md) — `canary_freshness` stage checks cassette freshness
- [Qualification](qualification.md) — replay anchors feed qualification bundles
