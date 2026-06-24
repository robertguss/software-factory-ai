# ADR-25: Bounded speculative parallelism per slice

Status: Accepted

Date: 2026-06-20

Bead: (to be assigned)

Amends: Law 27 (implementation width = 1). This ADR permits width > 1 within a
single slice while preserving the manual-merge, no-fleet posture across slices.

## Context

Law 27 fixes implementation width at one: one slice, one attempt in flight,
merge manual. The law was ratified to defer fleet/dispatcher/merge-queue
complexity and the coordination machinery (Agent Mail, file reservations) that a
shared-branch swarm requires. That reasoning is sound for cross-slice
parallelism.

It is overly broad for a different use of parallelism. The reliability gap means
a single model fails unpredictably on a fraction of attempts. The competitors
who name "race solution approaches and converge" as a goal cannot ship it
because they lack a trustworthy automatic judge. Conveyor has one: the
deterministic gate plus the calibrated `TrustScore` (ADR-23). With a real
arbiter, running several candidates for the same slice and keeping the best is
the cheapest reliability lever available, and it introduces none of the
coordination complexity Law 27 was protecting against — because the candidates
contend for one slice, in isolated sandboxes, and only one winner ever merges.

## Decision

For a single slice, the conductor may run N candidate attempts in parallel,
isolated sandboxes, and select one winner deterministically.

Candidates may differ by model, reasoning effort, seed, or prompt variant. Each
candidate runs in its own `Conveyor.Sandbox` workspace with no shared state and
no inter-candidate communication. Each is verified independently by the full
gate. The winner is selected by a declared, content-addressed policy: among
candidates that pass (or that earn auto-accept under ADR-23), choose the one
with the highest `TrustScore`, breaking ties by lowest cost. If none passes, the
slice fails or abstains exactly as a width-1 run would.

This is parallelism for reliability, not throughput. It does not introduce a
fleet, a dispatcher across slices, a merge queue, or shared-branch coordination.
Exactly one diff merges per slice; the cross-slice posture remains width 1 with
manual merge. Pre-registered pilot selection (ADR-22) is unaffected: the
selected slice set is still frozen before the first attempt; racing candidates
for a frozen slice does not change the set, and a slice that only passes via a
from-scratch human rewrite is still a release failure, not a rescue.

Speculative parallelism is opt-in per slice and gated by the cost governor:
candidates are spawned only when the expected value (the marginal P(pass) gain
predicted from the corpus for this archetype) justifies the marginal spend, and
N is bounded by the slice's risk tier.

## Consequences

A `RaceConductor` runs N attempts concurrently (BEAM `Task`/`DynamicSupervisor`)
and applies the winner-selection policy. Losing candidates' evidence is
retained, not discarded: the set of candidates and their verdicts is a labeled
dataset for calibrating model routing and the `TrustScore`.

Cost rises with N and must be governed. Without the cost governor (ADR-26 is
unrelated; see the Leverage Governor in the ideas doc) this feature is unsafe to
enable broadly; default N is 1 (width-1 behavior) and raised only by policy.

The determinism boundary holds: winner selection is a conductor computation over
recorded evidence, not an agent judgment, and is fully reproducible from the
recorded candidate verdicts.

## Implementation Notes

Candidate attempts must be true `RunAttempt` rows under the same slice so the
existing lifecycle, evidence, and ledger machinery apply unchanged; the race is
an orchestration layer above `RunSlice`, not a new execution path. Sandbox
isolation already provides the blast-radius separation required; no file
reservations or advisory locks are introduced.

Winner selection must be a pure function of the candidate verdict set plus the
policy digest, so a replay of the race reproduces the same winner.

## References

- docs/RADICAL-LEVERAGE-IDEAS.md, idea 3 (speculative parallelism), heresy on
  Law 27.
- Law 27 (width = 1) as recorded in docs/BRAINSTORM.md and the First Light
  handoff.
- ADR-22 (pre-registered pilot selection; the frozen set is preserved).
- ADR-23 (TrustScore as the winner-selection arbiter).
- `lib/conveyor/sandbox/`, `lib/conveyor/run_slice.ex`.
