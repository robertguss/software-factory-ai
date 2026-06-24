# ADR-11: Emergency stop and global budget reservation

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.11`

Gated milestone: P15-A4

## Context

Conveyor is allowed to run stochastic stations and provider-backed tools only
after Phase 1.5 establishes an Evidence Kernel. That kernel must include a
durable control plane before autonomy expands: retention, redaction, emergency
stop, global budget reservation, adapter health, and control-plane canaries.

The plan makes two laws non-negotiable:

- Emergency stop is always available. It blocks new starts, revokes or cancels
  active authority, pauses queued work, and requires a human decision to resume.
- No provider or scarce-tool spend is allowed without a prior reservation.
  Global circuit limits must be able to stop runaway work independently of any
  per-run limit.

Per-run budgets are not sufficient. A single bad graph can start many runs, and
an adapter or tool can fail in a way that consumes budget before local attempt
limits notice. Likewise, a stop button that only affects UI state or future
enqueueing is not a real safety control if active authority can keep publishing
claims or effects.

## Decision

Conveyor will implement emergency stop and budget reservation as canonical,
transactional control-plane resources, not as station-local conventions.

Emergency stop state is durable and scoped:

- `system` scope stops all projects.
- `project` scope stops one project.
- At most one current stop state exists per scope.
- Every engage and clear operation is recorded as an authority event with actor,
  reason, trace id, and, for resume, a `HumanDecision`.

When emergency stop is engaged for a relevant scope, the system must:

- prevent new station starts, provider calls, tool calls, claim publication, and
  external effects;
- pause queued work that has not started;
- cancel or revoke active station authority according to policy deadlines;
- make any incomplete cancellation explicit in evidence;
- require a human resume decision before returning to `clear`.

Budget control uses `BudgetEnvelope` and `BudgetReservation` resources. Every
provider or scarce-tool call must reserve capacity before the effect begins.
Reservations are scoped to system, project, run, or other policy-defined
subjects through their envelope, and are lifecycle tracked as `reserved`,
`committed`, `released`, `expired`, or `rejected`.

Budget reservation happens before any per-run budget debit. A call cannot start
unless the relevant global and project envelopes admit the reservation in the
same transactional decision path. Rolling windows, cost limits, token limits,
and concurrency limits are circuit breakers. A circuit can reject new
reservations even if a local run still has budget remaining.

Emergency stop and budget reservation decisions produce stable policy decisions,
trace context, and canary-visible evidence. They are part of qualification, not
best-effort observability.

## Consequences

- Provider and scarce-tool effects now have a mandatory admission step.
- Station code must be structured so authority can be revoked between durable
  steps and before effect publication.
- Queue uniqueness, retries, and per-run limits do not count as emergency or
  budget controls.
- Qualification fails if stop, cancellation/revocation, resume, reservation, or
  runaway-circuit canaries fail.
- Some useful work may be blocked by conservative budget circuits. That is an
  acceptable fail-closed outcome.

## Implementation Notes

- Use `EmergencyStopState` with fields for scope, project id, status, reason,
  actor, human decision id, engaged/cleared timestamps, and trace id.
- Use `BudgetEnvelope` for scope, currency, token/cost/concurrency/window
  limits, policy digest, and status.
- Use `BudgetReservation` for the subject, requested capacity, reservation
  expiry, committed actuals, status, policy decision id, and trace id.
- Check emergency stop before queue start, before provider/tool invocation, and
  before claim/effect publication.
- Treat cancellation or revocation misses as qualification evidence, not hidden
  operational noise.
- Keep adapter health integration separate: adapter circuits can narrow or
  expire authority, while ordinary coding quality misses alone must not open the
  adapter health circuit.

## References

- Bead `software-factory-ai-aamg.1.11`.
- Phase 1.5/2 plan, section 2.18, Phase 1.5 cutline.
- Phase 1.5/2 plan, section 3, laws 40 and 41.
- Phase 1.5/2 plan, section 4.6, `EmergencyStopState`, `BudgetEnvelope`, and
  `BudgetReservation`.
- Phase 1.5/2 plan, section 18.2, milestone P15-A4.
- Phase 1.5/2 plan, section 28.2, required ADR item 11.
