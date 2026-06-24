# ADR-24: Conductor-mediated in-loop verification

Status: Accepted

Date: 2026-06-20

Bead: (to be assigned)

Clarifies: ADR-06, ADR-07 (a read of the deterministic verifier is not an
instruction-authority transfer).

## Context

Today an implementer agent runs blind in its sandbox for the full duration, and
the gate judges only after the run completes. A full gate pass is expensive
(minutes, real spend), so the agent receives ground-truth feedback only once,
too late to use it within the attempt. The result is multi-round rework loops:
the agent guesses, the gate corrects, a new attempt is forged. Each round costs
a full sandbox run.

The deterministic gate stages (`lib/conveyor/gate/stages/*`) are pure functions
over a workspace and a contract. Several of them — diff scope, acceptance
mapping, contract lock, secret safety, and scoped test execution — can be
evaluated incrementally against an in-progress workspace. If the agent could
read that signal mid-flight, it would self-correct against ground truth instead
of guessing, collapsing most rework into the first attempt.

The concern is the determinism boundary. ADR-07 states that instruction
authority flows only from policy-compiled RoleViews and ToolContracts, never
from prose, and the broader law (ADR-06, ADR-15) is that the conductor owns
verdicts and agents own drafting. A naive "let the agent run the gate" would
blur that.

## Decision

The conductor may expose a read-only, scoped subset of the deterministic gate to
the implementer as a conductor-mediated tool, governed by a ToolContract. The
agent may query "which acceptance criteria am I currently failing, is my diff in
scope, did I touch a locked path, are there unredacted secrets" against its
working tree. The conductor computes the answer from the authoritative gate
stages and returns it.

This is a read, not an authority transfer. The agent never receives a verdict,
never closes a slice, never satisfies an obligation, and never gains the ability
to mutate policy or contracts. The authoritative gate still runs in full at
finalization on the recorded evidence; the mid-flight read is advisory to the
agent exactly as a compiler error is advisory to a programmer. The determinism
boundary is preserved: verdicts remain conductor-owned and are recomputed at the
gate.

The mid-flight subset is restricted. Stages that constitute the hidden oracle —
mutation and reference-solution survival (ADR-19), red-team checks, and any
scorer-only material (ADR-02) — must never be exposed to the implementer.
Exposing them would let the agent overfit to the adversary and defeat the
anti-vacuity guarantee. The mid-flight subset is limited to the
acceptance/scope/policy stages whose purpose is to tell the agent what the
contract already asks of it, never to reveal how it will be attacked.

## Consequences

The `AgentRunner` behaviour and adapters gain a conductor callback channel for
scoped read queries. The channel is policy-gated and logged as tool invocations
under the existing `RunBudgetGuard` accounting, so mid-flight checks count
toward the run budget and cannot be used to mine the verifier without cost.

Pass@1 is expected to rise materially; the primary measured outcome is the
reduction in rework rounds per accepted slice.

A new overfitting risk is introduced: an agent could tune its diff to the
visible acceptance stages while remaining wrong against the hidden oracle. This
is acceptable and intended to be caught precisely by keeping mutation,
reference-solution survival, and red-team stages out of the mid-flight subset
and in the final gate. The integrity sentinel (ADR-23 `TrustScore`) is the
backstop: a diff that passes the visible stages but fails the hidden oracle
abstains or fails.

## Implementation Notes

Mid-flight evaluation must reuse the exact stage implementations used at the
final gate to guarantee the agent reads the same logic that will judge it; there
must be no separate "preview" gate that can drift from the real one. Per-slice
gate scoping (the First Light M1b work) is a prerequisite, since the mid-flight
read must be scoped to the slice's own acceptance criteria.

The ToolContract for the read query declares it read-only, no-effects, and
budgeted, and records each invocation in the causal event log so the agent's use
of ground truth is itself auditable.

## References

- docs/RADICAL-LEVERAGE-IDEAS.md, idea 2 (verifier-in-the-loop).
- ADR-06 (one PolicyDecision interface), ADR-07 (instruction authority).
- ADR-19 (mutation/reference-solution as hidden oracle; do not expose).
- `lib/conveyor/gate/stages/`, `lib/conveyor/agent_runner.ex`,
  `lib/conveyor/policy/run_budget_guard.ex`.
