# ADR-01: Phase 1.5 insertion, four increments, and gate semantics

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.1`

Gated milestone: P15-A0

## Context

Phase 0/1 proved the station loop and gate canaries, but it did not yet prove live-agent outcome quality, replay authority, scoped qualification, or generated-contract readiness. Going directly to fleet, merge-queue, or broader Phase 2 execution would multiply an authority model that is still informal.

The Phase 1.5/2 program must preserve the two public release gates while creating smaller stopping points where evidence, schemas, and the generated-contract path can be tested before they become hard to change.

## Decision

Insert Phase 1.5 between Phase 1 and Phase 2, and deliver the combined program through four increments:

- P15-A Evidence Kernel: canonical identity, digests, policy decisions, RoleViews, ToolContracts, fenced station authority, effects, traces, artifact storage, controls, and evidence migration.
- P15-B Trust Qualification: permanent Battery, live adapter qualification, replay, verification integrity, diagnosis, and scoped QualificationGrants.
- P2-A Compiler Core: pure incremental compiler passes from immutable plan source snapshots into traceable graphs and static decision artifacts.
- P2-B Contract Foundry and serial pilot: executable contracts, obligations, Critic, approval roots, amendments, and a pre-registered pilot.

The two public gates remain `qualification_gate` and `phase2_gate`. `qualification_gate` issues an active grant for an exact scope from immutable evidence. `phase2_gate` proves approved generated contracts survive serial execution without hidden manual reconstruction. `compiler_structure_gate` is added only as an internal, non-authorizing checkpoint for Compiler Core structure; it never creates ContractLocks, approvals, implementer launches, or execution authority.

P15-A starts with a Phase-1 retrospective, frozen baseline digests, and one throwaway generated-contract vertical tracer. The tracer is non-authoritative and discarded after its findings are recorded in `PhaseNextDecision`.

## Consequences

Milestone IDs, evidence roots, schemas, gate commands, and implementation dependencies should follow the P15-A/P15-B/P2-A/P2-B shape. Phase 3 work remains blocked until both public gates pass. If P15-B produces only a narrower grant than requested, implementation must stop for targeted hardening before the affected Phase 2 scope is authorized.

The program can validly stop after P15-B with a qualified, diagnosable, single-slice factory. That is an accepted outcome, not a failed Phase 2.

## Implementation Notes

P15-A-core may unblock early P15-B corpus, scorer, adapter-conformance, and replay work only after it is dogfooded on the Phase-1 loop. P15-A-hardening is still required before `qualification_gate` can issue a release grant.

`PhaseNextDecision` records retrospective metrics, selected branches, tracer findings, evidence refs, and stop-the-line responses. P2 schema freeze waits until the tracer findings are reviewed.

Every gate command must make authority boundaries explicit: public gates authorize release progress only through their documented outputs; `compiler_structure_gate` reports structure and blocks Foundry work but grants no runtime authority.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md, sections 0, 0.3, 2.1, 18.1, 18.2, 18.3, 18.4, 25, and 28.2 item 1.
