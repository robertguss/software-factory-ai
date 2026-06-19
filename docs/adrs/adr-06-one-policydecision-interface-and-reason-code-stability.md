# ADR-06 - One PolicyDecision interface and reason-code stability

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.6`

Gated milestone: P15-A2 - PolicyDecision, ToolContracts, RoleViews, and output boundaries

## Context

Phase 1.5 makes policy decisions part of the permanent Evidence Kernel. The
plan requires every consequential authority path to cite a versioned
PolicyDecision with stable reason codes, and it treats hidden policy branches as
an invariant violation. Readiness, provider egress, tool invocation, autonomy,
waivers, approval invalidation, contract locking, budget reservation, and
emergency-stop resume all need the same auditable policy shape.

Without one interface, each UI, job, gate, or domain module can drift toward its
own policy input shape and its own interpretation of deny, default behavior, or
evaluator failure. That would make policy bypasses easy to introduce and hard to
test.

## Decision

All consequential policy questions use a typed DecisionContract and produce a
PolicyDecision. Domain modules must not call an untyped generic evaluator such
as evaluate/4 directly. Generated typed wrappers validate the request shape
before runtime policy evaluation.

A DecisionContract registry entry defines the decision key, subject kinds, input
schema, result schema, required evidence selectors, freshness policy, default
result, evaluator reference, evaluator version, and contract digest.

PolicyDecision results are limited to allow, deny, require_human,
not_applicable, and indeterminate. The indeterminate result represents evaluator
failure or unsupported policy input, fails closed, and remains distinct from a
policy-authored deny.

Reason codes are stable contract surface. They may be added through normal
schema evolution, but existing reason code meanings must not be silently
repurposed because tests, operator explanations, gates, and downstream
diagnosis depend on them.

## Consequences

- Every consequential action can be audited through a single PolicyDecision
  resource.
- Policy bypass testing can target one invariant: no authority path proceeds
  without a current typed decision.
- Evaluator failures become visible fail-closed states instead of looking like
  authored denials.
- New policy families require schema and registry work before implementation
  starts.
- Call sites lose the convenience of ad hoc policy checks, but gain consistent
  default-deny or require-human behavior.

## Implementation Notes

- Implement PolicyBundle validation, DecisionContract registry entries, typed
  request wrappers, and the PolicyDecision resource in P15-A2.
- Enforce default deny or require_human when policy input is unsupported.
- Ensure every domain action, job, gate, provider egress check, tool invocation,
  waiver, approval invalidation, lock, and budget decision stores or cites the
  relevant PolicyDecision.
- Add bypass fixtures that attempt alternate code paths through UI, jobs, and
  domain modules.
- Treat reason-code compatibility as part of schema evolution and operator
  documentation.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md
- Section 3, law 33
- Section 4.1.1, One auditable PolicyDecision layer
- Section 5.2, PolicyBundle, DecisionContract, and PolicyDecision
- Section 18.1, P15-A2 acceptance criteria
- Section 28.2, required ADR item 6
