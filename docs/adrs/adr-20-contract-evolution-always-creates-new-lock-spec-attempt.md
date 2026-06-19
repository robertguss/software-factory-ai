# ADR-20: Contract evolution always creates new lock/spec/attempt

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.20`

Gated milestone: P2-B6

## Context

Immutable attempts are useful only if their execution capsule cannot drift. If a contract correction can mutate an active ContractLock or RunSpec in place, evidence, retries, approvals, and post-run diagnosis become ambiguous.

Correction E states that a changed RunSpec always means a new RunAttempt. Law 20 forbids in-place attempt renegotiation, and law 7 keeps published semantic PlanRevisions immutable instead of allowing edits to rewrite prior meaning.

## Decision

Any change to a ContractLock or RunSpec terminates the prior immutable attempt cleanly and creates a new ContractLock, RunSpec, and RunAttempt. Contract faults are separate from implementation retries and do not consume an implementation-failure retry budget, but they never mutate history in place.

Material contract evolution uses PlanAmendmentProposal, impact analysis, materiality classification, deterministic redlines, affected-root previews, and the required HumanDecision path. Review-only corrections may preserve locks when they do not alter semantic, authority, evidence, interface, decision, verification, or grant inputs.

No negotiation mode may modify an active attempt in place. Even eligible pre-attempt auto-accept deltas must create new authority roots, ContractLock, RunSpec, and RunAttempt.

## Consequences

Old evidence remains interpretable against old roots and grants. Diagnosis can distinguish implementation failure from contract fault, and retry budgets are not polluted by impossible or corrected contracts.

This creates more historical records, but it prevents silent authority drift. Selective reuse remains possible only when derivation proves affected artifacts are unchanged; uncertainty fails wide.

## Implementation Notes

P2-B6 implements PlanAmendmentProposal and impact analysis, materiality policy, human-gated and shadow modes, affected-pass/subgraph recompilation, interface/obligation/grant/root invalidation, and new-lock/spec/attempt enforcement.

Acceptance must prove that implementers cannot self-declare nonmaterial changes; acceptance, obligation, decision, hard-constraint, scope, compatibility, or waiver weakening is material; unaffected digests remain only when derivation proves safety; shared interface changes invalidate consumers; review-only corrections preserve locks; old evidence remains interpretable; negotiation round limits hold; and a new lock/spec never reuses an old attempt.

## References

- Bead software-factory-ai-aamg.1.20
- Phase 1.5/2 plan Correction E
- Phase 1.5/2 plan section 11, "Plan amendments, contract disputes, and staged micro-negotiation"
- Phase 1.5/2 plan section 18.4, "P2-B6 - Amendments, staged negotiation, and selective invalidation"
- Phase 1.5/2 plan section 28.2 item 20
- Laws 7 and 20
