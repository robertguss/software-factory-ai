# ADR-22: Pre-registered pilot selection

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.22`

Gated milestone: P2-B7

## Context

The Phase 2 pilot is the integration test for the compiler, Contract Foundry,
qualified loop, evidence model, recovery paths, and operator workflow. If the
selected Slices can change after outcomes are visible, the pilot can quietly
turn into an easy-case demonstration. Failed selections could be replaced,
compiler weakness could be hidden, and from-scratch human contract rewrites
could mask whether generated contracts actually executed.

The plan defines `PilotSelection` as an explicit resource with
`planning_bundle_id`, `selection_policy_digest`, selected and excluded Slice IDs,
coverage classes, a `selection_digest`, and `frozen_at`. It is immutable once the
first selected implementation attempt starts.

## Decision

Pilot selection is pre-registered before the first selected implementation
attempt. `PilotSelection` is frozen by digest and records:

- the planning bundle being evaluated;
- the selection policy digest;
- selected Slice IDs;
- required coverage classes;
- excluded Slice IDs with reasons;
- the selection digest;
- the freeze timestamp.

For a pilot with 12 or fewer machine-executable Slices, every machine-executable
Slice is selected. For larger pilots, selection must follow a policy coverage
sample declared before execution. The selected set cannot change after outcomes,
and failed selections cannot be replaced.

The pilot must include graph/interface/risk/human-verification coverage. A
selected generated contract that needs a from-scratch human rewrite merely to
execute is a release failure, not a successful rescue.

## Consequences

Pilot evidence remains interpretable because success and failure are measured
against a frozen set, not a post-hoc sample. The retrospective can separate
plan, compiler, context, implementation, evidence, adapter, and operator
failures without selection bias.

This makes the pilot less convenient: a bad selected Slice can park or fail the
run rather than being swapped out. That is intentional. Easy-case cherry-picking
and hidden compiler weakness are more dangerous than a smaller apparent success
rate.

## Implementation Notes

P2-B7 implements `PilotSelection`, the pre-registration command, serial
execution through the qualified loop, and the pilot retrospective/Chronicle.
The selection artifact should be content-addressed and referenced by
`phase2_gate`.

Acceptance must prove the selected set never changes after outcomes, no failed
selection is replaced, every failure receives typed comparison/diagnosis/recovery,
unrelated ready Slices can continue when one Slice is parked, and the final
report separates failure classes. Pilot mutation after execution begins is a
hard `phase2_gate` failure.

## References

- Phase 1.5/2 plan resource `PilotSelection`.
- Phase 1.5/2 plan section 17.4, "Phase-2 contract/compiler gate - hard correctness thresholds".
- Phase 1.5/2 plan section 18.4 P2-B7, "Pre-registered generated-plan pilot".
- Phase 1.5/2 plan section 28.2 item 22.
