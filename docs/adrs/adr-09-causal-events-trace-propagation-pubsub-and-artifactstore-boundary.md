# ADR-09 - Causal events, trace propagation, PubSub, and ArtifactStore boundary

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.9`

Gated milestone: P15-A3 - Station leases, fencing, effect receipts, trace
events, and ArtifactStore

## Context

Conveyor needs durable replay and diagnosis without flooding Postgres with token
streams, prompt payloads, tool transcripts, patches, cassettes, and static
bundles. It also needs low-latency UI progress without treating transient UI
messages as history.

The plan separates canonical authority from high-volume observation exhaust.
Postgres remains the transactional source of truth for canonical resources,
AuthorityEvents, leases, policy decisions, grant and approval metadata, artifact
pointers, derivation indexes, and transactional outbox rows. ArtifactStore owns
large immutable blobs and ObservationSegments.

## Decision

AuthorityEvent is the low-volume, transactional, append-only audit and recovery
record for consequential state changes. It lives in Postgres with per-stream
sequence or version, causation, correlation, trace context, payload reference,
fencing epoch, and policy-decision metadata.

ObservationSegment is high-volume transcript, token, tool-output, and telemetry
evidence. It lives in ArtifactStore and never independently changes authority.
Large prompts, context packs, event streams, patches, cassettes, static bundles,
and analytical archives are stored as blobs. Postgres stores digest, pointer,
sensitivity, availability, retention, and lineage metadata rather than raw
exhaust.

A run creates one trace_id. Jobs, StationRuns, AuthorityEvents,
ObservationSegments, EffectReceipts, logs, provider request IDs where available,
and artifacts carry the trace context. Internal trace identifiers are sent to
providers only through documented adapter metadata when sensitivity policy
permits; otherwise provider request IDs are correlated locally.

Phoenix.PubSub is best-effort low-latency progress notification, not durable
history. LiveView and other projections catch up from committed durable segments
and ignore duplicate or out-of-order PubSub messages by sequence number.

No design claim depends on a distributed transaction between Postgres and the
ArtifactStore. Blob bytes are staged and digest-verified before publication; a
Postgres transaction commits the artifact pointer, final state, AuthorityEvent,
and outbox record together; notifications publish from the outbox. A sweeper
garbage-collects staged but uncommitted blobs.

LocalCAS is the required default ArtifactStore backend. S3-compatible storage is
optional and must pass the same digest, authorization, and conformance contract.
An external broker such as Kafka, RabbitMQ, or Redis requires a later ADR based
on measured throughput, isolation, or multi-region need.

## Consequences

- Canonical state remains transactional in Postgres while large exhaust avoids
  Postgres and WAL bloat.
- PubSub can be dropped or duplicated without losing evidence or replay truth.
- Replay and diagnosis can correlate events, effects, logs, provider requests,
  and artifacts through one trace context.
- ArtifactStore backend substitution is possible without creating a second
  source of truth.
- Implementations must handle staged blobs and crash recovery explicitly because
  there is no Postgres-to-CAS distributed commit.

## Implementation Notes

- Implement AuthorityEvent, ObservationSegment, EventRouter, EventSegmentWriter,
  ArtifactAddress, ArtifactStore.LocalCAS, and backend conformance tests in
  P15-A3.
- Use ArtifactAddress to separate trust-domain identity, content digest,
  optional ciphertext digest, opaque storage key, encryption key reference, and
  storage backend.
- Authorize head_blob before revealing artifact existence.
- Buffer canonical events in bounded memory, assign sequence numbers, flush
  immutable JSONL segments by byte or time threshold, and commit segment
  manifests at station completion or reconciliation.
- Ensure LiveView reconnect reconstructs ordered events from durable segments
  before subscribing to later PubSub notifications.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md
- Correction P, immutable evidence does not imply infinite retention or Postgres
  payload bloat
- Section 3, laws 42-43 and 48
- Section 4.6, state, exhaust, and artifact architecture
- Section 4.7, trace and event model
- Section 5.8, ArtifactStore, event exhaust, and analytical archive
- Section 13.6, event streaming and durable catch-up
- Section 13.7, ArtifactStore implementation
- Section 18.1, P15-A3 acceptance criteria
- Section 28.2, required ADR item 9
