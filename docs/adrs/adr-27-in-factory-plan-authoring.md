# ADR-27: In-factory plan authoring (Plan Foundry)

Status: Accepted

Date: 2026-06-20

Bead: (to be assigned)

Overturns: ratified decision 6c (multi-model planning is external/manual for v1;
factory input is a finished hybrid plan). Preserves: decision 6d (Test Architect
role) and ADR-19 (compiler-owned falsifier seeds).

## Context

Ratified decision 6c scopes planning out of the factory: the human authors a
finished hybrid plan externally, and the factory ingests it. The reasoning was to
keep v1 scope small and treat "pull planning in later" as merely more agents.

For a single developer optimizing raw shipping leverage, this draws the boundary
in the wrong place. Executing slices faster has diminishing returns once the loop
works; the durable bottleneck for one person is turning rough intent into a
great, contract-bearing plan — today that means hand-authoring a large plan
document before any code. The First Light result confirmed the downstream loop
can build gate-passing software from a good plan; it did not address where the
good plan comes from.

The machinery to author plans already exists and is pointed only at
human-written input. `Conveyor.ContractForge` drafts AgentBriefs from
requirements across seven archetype templates; `Conveyor.ContractCritic` runs ten
required adversarial lenses (including intent fidelity, scope delta, hidden
decision, and approval cognitive load); and `Conveyor.Readiness` already defines
a `:needs_clarification` status — a built-in slot for "ask the human" that has no
interrogator behind it.

## Decision

The factory may author the plan from a short statement of intent, subject to the
same separation of duties that governs implementation.

The operator provides a paragraph of intent. The factory drafts the plan — epics,
slices, contracts, acceptance criteria — using the contract-forge machinery. The
contract critic, a distinct actor, runs its ten lenses adversarially against the
factory's own draft. Where the draft contains genuine ambiguity the compiler
cannot resolve, the slice enters `:needs_clarification` and an interrogator
surfaces the minimal disambiguating questions to the operator. The operator
answers questions and approves the plan at the existing single approval
checkpoint; only then does autonomous execution begin.

Separation of duties is preserved and is the reason this is safe. The drafter
(contract forge), the critic (contract critic), and the implementer are three
distinct actors; no actor authors and then implements against its own contract,
and no actor approves its own contract — the human does. Decision 6d (the Test
Architect role) and ADR-19 (the compiler, not the implementer, owns falsifier
seeds) are unchanged: required tests and falsifier seeds are still authored
independently of the implementer, whether the surrounding plan was written by a
human or drafted by the factory.

This overturns 6c's "planning is external" stance while keeping 6c's deeper
intent — that the human owns intent and approval. The human still owns the intent
(the paragraph) and the gate (approval); the factory owns the mechanical
expansion from intent to a critiqued, machine-checkable plan.

## Consequences

A draft plan that is wrong wastes effort, so the critic gate and the human
approval checkpoint are load-bearing and must run before any execution. A plan
the factory cannot make `handoff_ready` (the existing `plan_audit` bar) is not
executed; it is returned to the operator with the blocking findings.

The operator's effort shifts from authoring a specification to answering a small
number of sharp questions and approving. This is the single largest solo-leverage
change in the roadmap because it moves the human out of the most time-consuming
phase while keeping them in the two phases only they can own: stating intent and
granting approval.

Quality is capped by the critic's trustworthiness on machine-drafted (not just
human-drafted) plans; the critic's calibration on generated input becomes a
first-class concern and should itself be measured.

## Implementation Notes

Reuse the existing `plan_audit` / `handoff_ready` bar as the gate on factory-
drafted plans exactly as for human-drafted ones; there must be no weaker standard
for machine-authored plans. The interrogator consumes `:needs_clarification`
findings and must ask only questions the compiler genuinely cannot resolve, to
keep the operator's question budget small.

The factory's draft and every critic finding are recorded so the path from intent
paragraph to approved plan is event-sourced and auditable, and so the
intent-to-plan expansion itself becomes corpus the system can learn from.

## References

- docs/RADICAL-LEVERAGE-IDEAS.md, idea 5 (Plan Foundry), heresy H3.
- docs/BRAINSTORM.md decisions 6c (overturned) and 6d (preserved).
- `lib/conveyor/contract_forge/`, `lib/conveyor/contract_critic/`,
  `lib/conveyor/readiness.ex`.
- ADR-19 (compiler-owned falsifier seeds, preserved).
