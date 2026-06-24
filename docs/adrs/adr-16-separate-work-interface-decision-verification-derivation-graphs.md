# ADR-16: Separate work/interface/decision/verification/derivation graphs

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.16`

Gated milestone: P2-A3

## Context

The Phase 1.5/2 compiler needs to reason about execution order, interface
readiness, human decisions, verification, and artifact invalidation. A single
dependency table would collapse unrelated meanings into Slice edges, creating
false serialization, pairwise interface edges, fake decision blockers, and
unsafe selective reuse.

The plan already distinguishes work semantics from interface, decision,
verification, and derivation semantics. Laws 17 and 39 make that separation
mandatory: work dependencies model execution or integration order, and selective
invalidation is allowed only when queryable derivation edges prove that
semantic, authority, and evidence inputs remain valid.

## Decision

Conveyor will maintain separate graph/relationship models for work, interfaces,
decisions, verification, and derivation.

- The work graph contains only execution-hard and integration-order Slice
  dependencies.
- The interface graph contains InterfaceContracts, SliceInterfaceBindings,
  provider/consumer versions, compatibility expectations, and readiness.
- The decision graph contains SliceDecisionBlocks linked to HumanDecision
  records.
- Verification relationships are represented by VerificationObligations,
  evidence, waivers, and falsifier coverage rather than fake Slice dependencies.
- The derivation graph is the ArtifactInput index describing which semantic,
  authority, evidence, advisory, and presentation inputs produced each artifact.

When derivation or consumer-impact confidence is low, Conveyor fails wide by
invalidating a broader scope instead of preserving stale authority.

## Consequences

This increases schema surface area, but it keeps graph edges honest and
queryable. Likely-file overlap, unresolved human decisions, missing evidence,
and consumer compatibility issues can block readiness without pretending to be
execution dependencies.

Selective invalidation becomes defensible because reuse is based on declared and
observed inputs, not timestamps or unrelated Slice edges. Structural dry-runs
can report topology and unresolved decisions without fabricating schedule or
cost certainty.

## Implementation Notes

P2-A3 implements SliceDependency for work-only edges, InterfaceContract and
SliceInterfaceBinding for provider/consumer compatibility, SliceDecisionBlock
for human decision blockers, preliminary VerificationObligations, and
ArtifactInput derivation indexes.

Acceptance must prove that likely-file overlap does not create a hard work edge,
provider/consumer schemas and versions resolve or block correctly, human
decisions are not encoded as fake Slice edges, unsafe atomicity splits are
rejected, every authority artifact has derivation inputs, low impact confidence
fails wide, and structural simulation uses no fabricated economics.

## References

- Bead software-factory-ai-aamg.1.16
- Phase 1.5/2 plan section 4.5, "Three separate graphs"
- Phase 1.5/2 plan section 18.4, "P2-A3 - Work, interface, decision,
  verification, and derivation graphs"
- Phase 1.5/2 plan section 28.2 item 16
- Laws 17 and 39
