# ADR-08 - Station leases/fencing and EffectReceipts

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.8`

Gated milestone: P15-A3 - Station leases, fencing, effect receipts, trace
events, and ArtifactStore

## Context

Oban uniqueness prevents some duplicate job insertion, but it does not prove
that the current worker still owns execution authority. A stale worker can wake
after lease expiry and attempt to write state or publish an effect after a newer
retry has taken ownership.

External effects also have ambiguous failure modes. A provider call, credential
issuance, sandbox start, process execution, repository publication, or object
store commit may have been accepted externally even if the worker crashed before
recording local success.

## Decision

Every durable StationRun uses a database lease with a monotonically increasing
lease epoch and fencing token. Every state transition, artifact publication,
ToolInvocation, StationEffect, EffectAttempt, and EffectReceipt carries the
current epoch. Writes and effect publications from older epochs are rejected.

Every external effect declares delivery semantics: idempotent, externally
deduplicated, reconcilable, or non_reconcilable. Effects carry a stable
idempotency key, fencing token, request digest, and durable receipt. A retry
must first reconcile any pending or ambiguous receipt before repeating or
compensating an effect.

EffectAttempt and EffectReceipt are separate resources. An EffectAttempt records
that the effect started and whether the outcome is started, externally_accepted,
failed, or outcome_unknown. An EffectReceipt records observed result digest,
external correlation ID when available, reconciliation status, trace ID, and
observed time.

A database fencing token always fences local authority publication. It fences an
external system only when that system supports native conditional or fenced
writes. Non_reconcilable external effects are prohibited at L1 unless explicitly
human-authorized.

## Consequences

- A retry can safely take ownership without allowing late stale-worker writes.
- Duplicate effects become reconciled, compensated, parked as ambiguous, or
  failed closed instead of silently repeated.
- External integrations must expose idempotency, correlation, and reconciliation
  behavior before they can be treated as normal effects.
- Station worker code must carry lease epoch through all state writes and effect
  records.
- Crash recovery becomes more explicit, but it requires more durable records.

## Implementation Notes

- Implement StationRun lease epoch, heartbeat, expiry, and stale epoch rejection
  in P15-A3.
- Add EffectAttempt and EffectReceipt schemas and wire them through every
  external effect path.
- Define station identity as run_or_planning_id, station_key,
  station_spec_digest, and attempt_no.
- Add stale-worker meta-canaries and crash-boundary tests for before external
  call, after external accept before receipt, after receipt before pointer
  commit, after blob staged before database commit, after database commit before
  outbox publish, after outbox publish before worker ack, and after permit
  renewal before station publication.
- Treat pure pass-cache reads and Cassette lookup as read effects; declare
  provider calls, credential issuance, sandbox starts, process execution,
  repository publication, and object-store multipart commits as external
  effects.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md
- Correction M, queue uniqueness is not execution ownership
- Section 3, laws 31-32
- Section 5.2, EffectAttempt and EffectReceipt
- Section 13.1, Station leases, fencing, and idempotency
- Section 16.1.1, trust-spine state-machine models
- Section 16.1.2, crash-boundary tests
- Section 18.1, P15-A3 acceptance criteria
- Section 28.2, required ADR item 8
