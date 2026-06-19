# ADR-03: Scoped QualificationGrant and impact/expiry semantics

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.3`

Gated milestone: P15-B8

## Context

A global "qualified" badge would overstate what the evidence proves. Qualification depends on adapter behavior, profile, prompt family, archetype, change class, language/toolchain, repository risk, environment, policy, verification capability, and autonomy. Runtime conditions such as budget, adapter health, emergency stop, and current approvals also matter, but they are not the same kind of fact as immutable qualification evidence.

The system needs a durable evidence artifact for what has been proven and a separate operational authority artifact for whether this exact run may proceed now.

## Decision

`QualificationGrant` is immutable scoped evidence, not a runtime lease. It is superseded only by semantic drift, expiry, explicit revocation, or evidence invalidation. It covers exact combinations of adapter capability snapshot, agent profile and prompt family, archetype and change class, language/toolchain family, repository risk class, environment fingerprint, policy bundle, verification capabilities, and maximum autonomy.

Grant scope is represented by a versioned `QualificationScopeLattice`. Evidence is classified as direct, inherited, or supporting only. Inheritance is never assumed; it requires an audited monotonic rule. Until such rules exist, inheritance defaults to none. Each grant records direct and inherited strata, inheritance rule refs, unassessed strata, and the worst required stratum result.

Every effectful `PlanningRun`, `RunAttempt`, station, provider call, or tool call also requires a short-lived `AdmissionPermit` and repeated `PermitCheckpoint` validation. The grant answers what the evidence established. The permit answers whether this immutable subject may operate now under current approval roots, policy, environment, budget, control generation, capability set, and grant status.

`QualificationImpact` previews which grants and cases a proposed change affects. Requalification is impact-based rather than all-or-nothing.

## Consequences

Admission cannot rely on a valid grant alone. Stops, budget revocation, approval root changes, control generation changes, adapter circuit state, or environment mismatch can park or deny the operation even when the underlying grant remains valid.

A CRUD grant cannot authorize an irreversible migration, and an observe-only adapter cannot receive write autonomy. A broader requested scope fails if the evidence supports only a narrower grant.

Long-running attempts must park on checkpoint failure with typed reasons such as `permit_expired`, `grant_expired_or_revoked`, `adapter_circuit_open`, `budget_revoked`, `emergency_stopped`, `environment_mismatch`, or `authority_root_invalidated`.

## Implementation Notes

`QualificationGrant` carries evidence root digest, scope ref and digest, adapter capability snapshots, agent profiles, archetypes, change classes, language/toolchain keys, risk classes, policy bundle digest, environment fingerprint digest, deployment profile digest, verification capability refs, max autonomy, success bands, limitations, waivers, issue and expiry timestamps, invalidation triggers, status, and supersession link.

`AdmissionPermit` binds spec digest, grant id, effective capability set, authority roots, policy bundle, environment fingerprint, budget reservations, control generation, issue/expiry, and permit digest. It may be renewed for the same immutable attempt, but semantic drift requires a new lock, spec, and attempt.

Every admission check records a `PolicyDecision` proving a current grant covers the requested scope.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md, sections 0.3, 2.8, 2.17, 3 law 29, 5.3, 17.2, 18.2 P15-B8, and 28.2 item 3.
