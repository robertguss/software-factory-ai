# ADR-26: Autonomous plan amendment from verification failure

Status: Accepted

Date: 2026-06-20

Bead: (to be assigned)

Builds on: ADR-14 (selective recompilation), ADR-16 (derivation graph), ADR-20
(contract evolution creates new lock/spec/attempt). Reconciles with ADR-22
(pilot freeze) and ADR-07/13/19 (separation of duties).

## Context

The factory currently treats the plan as frozen and the implementer as the thing
that must conform. When a slice fails the gate, the failure is attributed to the
code, and the recovery path is rework. But some failures are not code failures:
the acceptance criterion may be impossible, internally contradictory, or
under-specified — the contract is wrong, not the diff. With a frozen plan the
only outcomes are an infinite rework loop or a park, and the operator must
manually diagnose that the plan, not the agent, is at fault. This is the spec
under-specification problem the whole field leaves open: nobody closes the loop
from failed verification back to an automatic spec amendment.

The machinery to close it already exists and is never invoked from a gate
failure. `Conveyor.Planning.PlanAmendments.propose/1`
(`lib/conveyor/planning/plan_amendments.ex`) computes an amendment proposal via
`InvalidationPreview.preview_invalidation` and `ImpactPreview.build`, returning
the affected and downstream refs, the invalidated artifacts, and a status of
`:accepted` or `:human_review_required`. Selective recompilation (ADR-14) and the
derivation graph (ADR-16) already support re-deriving only the affected slices.
ADR-20 already requires that any contract evolution create a new lock, spec, and
attempt.

## Decision

When a gate failure is classified as a contract defect rather than a code defect,
the conductor automatically calls `PlanAmendments.propose/1`, computes the blast
radius, and surfaces the proposal to the operator for one decision. On approval,
only the affected slices are re-derived; on rejection, the slice returns to the
normal rework or park path.

Amendments are proposed, never auto-applied to acceptance contracts. Separation
of duties (ADR-07, ADR-13, ADR-19) is non-negotiable: the implementer that wrote
the code may never author, weaken, or approve the contract it is being judged
against. The amendment proposer is a distinct actor (the compiler/contract-forge
side), the contract critic challenges the proposal, and a human approves. An
agent-suggested amendment that would relax an acceptance criterion to make a
failing diff pass is the exact failure mode the boundary exists to prevent and
must be rejected by construction, not by judgment.

Classification of a failure as contract-defect vs code-defect is itself a
recorded, conductor-side decision driven by the failure taxonomy
(`Conveyor.Retrospective` already computes it; this ADR wires it to drive
routing). A misclassification that treats a code bug as a spec bug must be cheap
to reverse: the default bias is code-defect, and contract-defect routing requires
either an explicit taxonomy signal or operator confirmation.

Pilot integrity (ADR-22) is preserved. During a frozen pilot, an amendment that
rescues a selected slice does not silently swap it out of the measured set; the
amendment and its trigger are recorded as part of the pilot outcome. A rescue
that amounts to a from-scratch human rewrite of a generated contract remains a
release failure under ADR-22, not a success.

## Consequences

Every contract amendment follows ADR-20: a new ContractLock, RunSpec, and
RunAttempt, with the prior contract retained immutably. The amendment, its
trigger finding, its blast radius, and its approval are appended to the ledger so
the plan's evolution is fully event-sourced and never silently drifts.

The operator's role shifts from debugging code to satisfy a possibly-wrong spec
toward adjudicating spec changes — the higher-value decisions. The initial plan
no longer has to be perfect; it improves as the factory runs.

A new abuse surface appears (relax-the-contract-to-pass) and is closed by the
separation-of-duties enforcement above plus the contract critic's
intent-fidelity and scope-delta lenses, which must run on every proposed
amendment exactly as they run on an original contract.

## Implementation Notes

The failure-taxonomy classifier must be deterministic and recorded; route
Context-Pack Miss to re-scout, Execution Failure to rework, and Contract/Brief
defect to `PlanAmendments.propose`. Bidirectional sync writes an approved
amendment back to the prose constitution (the human-readable plan) so the
operator's source of truth and the work-graph projection never diverge (ADR-16).

The proposal's `:human_review_required` status is the default for any amendment
touching an acceptance criterion; `:accepted` (no human) is permissible only for
amendments that do not alter acceptance semantics (for example, a corrected file
pointer or a non-semantic clarification).

## References

- docs/RADICAL-LEVERAGE-IDEAS.md, idea 4 (the self-amending plan) and idea 7
  (failure-taxonomy routing), heresy H3.
- `lib/conveyor/planning/plan_amendments.ex`,
  `lib/conveyor/evidence/invalidation_preview.ex`, `lib/conveyor/retrospective.ex`.
- ADR-14, ADR-16, ADR-20, ADR-22, ADR-07, ADR-13, ADR-19.
