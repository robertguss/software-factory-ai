# ADR-17: Hierarchical authority/review/archive roots

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.17`

Gated milestone: P2-B4

## Context

Conveyor needs approvals, review presentations, archived bundles, and execution authority to remain distinguishable. A review-only correction must not invalidate execution authority, while an interface, waiver, policy, or semantic change must invalidate the exact authority that depends on it.

Law 8 requires approval to bind to scoped digest roots. Law 38 states that presentation bytes must not silently change execution authority. Correction L also separates content digests, authority roots, review roots, and archive roots so approvals can bind to the exact authority and review material shown to the actor.

## Decision

Conveyor will compute four domain-separated root families from canonical RootManifests:

- shared_authority_root for PlanRevision, constraints, shared policy, grants, common interfaces, and shared decisions;
- epic_authority_root for each Epic's Slice contracts, obligations, tests, dependencies, waivers, and Epic interfaces;
- review_root for the exact approval projection shown to the human reviewer;
- archive_bundle_root for authority roots, review roots, and non-authoritative supporting evidence.

The approval record is not included as a leaf in the root it signs. Each RootManifest declares its root kind, version, canonicalization profile, hash algorithm, and sorted entries so roots cannot be confused across domains or silently omit subject classes.

## Consequences

Partial reapproval becomes honest: a review-only erratum can update the review/archive domain without changing execution authority, while semantic, waiver, policy, grant, interface, or obligation changes alter the authority roots they actually affect.

The model adds digest and manifest bookkeeping, but it prevents circular signatures and makes stale approval diagnosis precise. UI, static reports, and CLI output must all derive from the same canonical bundle rather than inventing their own approval summaries.

## Implementation Notes

P2-B4 implements ContextAssemblyManifest handling, prompt dry-compile, shared and Epic authority roots, review roots, archive roots, canonical attestations, and the deterministic Factory Chronicle.

Acceptance must prove that critical context drops fail before provider use, review-only changes do not alter authority roots, semantic/waiver/policy changes alter the correct roots, approval records are excluded from signed roots, summaries cannot hide blockers, and UI/static/CLI projections derive from the same bundle.

## References

- Bead software-factory-ai-aamg.1.17
- Phase 1.5/2 plan Correction L
- Phase 1.5/2 plan section 8, digest domains and RootManifest
- Phase 1.5/2 plan section 18.4, "P2-B4 - Prompt budgets, layered roots, static bundle, and deterministic Chronicle"
- Phase 1.5/2 plan section 28.2 item 17
- Laws 8 and 38
