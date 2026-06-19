# ADR-10 - Retention/redaction/GC and active-authority preservation

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.10`

Gated milestone: P15-A4 - Retention, redaction, emergency stop, global budget, and adapter health primitives

## Context

Conveyor records evidence, cassettes, prompts, event exhaust, tool transcripts,
patches, diagnosis records, and authority roots. Keeping everything forever is
not acceptable, but deleting evidence blindly can destroy current authority,
auditability, replay, incident diagnosis, or legal-hold obligations.

The plan treats immutability and retention as separate concerns. Immutable
evidence may still have lifecycle policy, redaction, compaction, archival, or
erasure. Erased or unavailable evidence must be explicit in comparisons rather
than silently treated as inspectable because a digest remains.

## Decision

Every artifact receives a policy-derived retention class, availability state,
and optional legal or audit hold. Retention policy is selected by deployment
context and artifact role rather than hardcoded as one global TTL.

Garbage collection, compaction, redaction, and erasure must preserve active
authority evidence. No retention rule may erase a blob or record referenced by
an active grant, approval, ContractLock, legal hold, unresolved incident, or
required replay anchor.

The deterministic garbage collector must perform reference and derivation checks
before deletion, support dry-run and apply modes, write tombstone or erasure
events with reason and actor or policy, and distinguish available, cold,
redacted, erased, and unavailable states.

Erased evidence becomes explicit incomparable evidence. The system must not
pretend an erased blob remains inspectable merely because its digest is known.
Sensitive artifacts support secure erasure and key destruction where the backend
permits, while preserving enough metadata to explain why comparison is now
incomparable.

Redaction and sensitivity scanning run before event or Cassette seal so raw
provider output, secrets, restricted-evaluation data, hidden fixture knowledge,
or sensitive internal identifiers do not enter reusable archives.

## Consequences

- Retention can control storage growth without undermining current authority.
- Legal and audit holds override ordinary expiration.
- Replay and diagnosis can distinguish missing, redacted, erased, cold, and
  unavailable evidence instead of collapsing them into success or failure.
- Secure deletion depends on backend capabilities and encryption-key handling,
  so ArtifactStore implementations must expose those semantics.
- GC becomes part of the trust spine and needs state-machine, restore, and
  retention tests rather than being treated as background cleanup only.

## Implementation Notes

- Implement retention classes, legal and audit holds, GC dry-run and apply,
  erasure tombstones, and availability states in P15-A4.
- Run redaction and sensitivity scans before sealing event segments and
  Cassettes.
- Add state-machine tests for artifact staged, committed, GC, and tombstone
  transitions.
- Add scheduled or release retention/restore tests proving active references and
  holds are preserved and erased or unavailable evidence becomes incomparable.
- Preserve selected successes, failures, anchors, incidents, approvals, locks,
  and grant evidence according to policy even when raw exhaust expires.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md
- Correction P, immutable evidence does not imply infinite retention or Postgres payload bloat
- Section 3, law 47
- Section 5.9, Artifact lifecycle and retention
- Section 15.1, Evidence Kernel threats and defenses
- Section 16.1, retention/restore testing
- Section 16.1.1, trust-spine state-machine models
- Section 18.1, P15-A4 acceptance criteria
- Section 28.2, required ADR item 10
