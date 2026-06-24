# ADR-18: Interface lock/compatibility authority

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.18`

Gated milestone: P2-B1

## Context

Contracts need explicit authority over public and cross-Slice interfaces without
freezing internal implementation detail. If every internal choice becomes a
strict interface promise, the compiler will block useful refactoring and force
unnecessary approvals. If public or cross-Slice surfaces are not locked,
consumers can be broken without a visible authority change.

Law 15 requires no interface over-freezing: public and cross-Slice interfaces
receive explicit locks, while internal implementation choices stay free unless a
human decision says otherwise.

## Decision

InterfaceContract is the authority boundary for interface promises. Each
contract records the interface key, kind, stability, owner Slice, version, lock
level, compatibility policy, schema reference or digest where applicable,
deprecation policy, affected consumers, and claim references.

The supported lock levels are:

- strict;
- compatible_superset;
- review_required;
- informational.

Strict is reserved for genuinely public or cross-Slice surfaces. Internal
implementation details default away from strict authority unless an explicit
human decision or contract scope makes them part of the interface.

Bindings express provides, requires, or modifies relationships. Direction
belongs in SliceInterfaceBinding rather than in the interface identity itself.

## Consequences

The system can block incompatible public or cross-Slice changes, require review
for risky changes, and permit compatible supersets without treating every
implementation detail as frozen. Consumers get explicit compatibility
expectations and version ranges, while implementers retain internal freedom.

Contract authors must classify interface stability and lock levels carefully.
Ambiguous interface boundaries become contract-quality failures instead of
hidden assumptions.

## Implementation Notes

P2-B1 implements upgraded AgentBrief/contract schema, archetype templates,
interface locks, compatibility, rollout and migration safety, deterministic
VerificationObligation derivation, compiler-derived falsifier seeds, and
contract-author RoleView normalization.

Acceptance must prove that every contract states current, desired, non-goal,
scope, and recovery behavior; public/cross-Slice interface ownership and
compatibility are explicit; internal freedom is preserved; machine-checkable ACs
have falsifying conditions and seeds; scope additions require approval; and
every Slice explains why it is independently verifiable.

## References

- Bead software-factory-ai-aamg.1.18
- Phase 1.5/2 plan section 8, "Interface lock levels"
- Phase 1.5/2 plan section 9.1, "InterfaceContract value shape"
- Phase 1.5/2 plan section 18.4, "P2-B1 - Contract Forge, archetypes,
  interfaces, obligations, and falsifier seeds"
- Phase 1.5/2 plan section 28.2 item 18
- Law 15
