# ADR-04: Canonical schema registry, DigestRef, and canonicalization

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.4`

Gated milestone: P15-A1

## Context

The Evidence Kernel, Battery, grants, compiler artifacts, approvals,
attestations, migrations, and offline verification all depend on stable artifact
identity. Older documents use ambiguous capability IDs and field-specific
`*_sha256` names, while new implementation needs algorithm agility, canonical
bytes, schema lineage, and explicit digest domains.

Without one registry and canonicalization profile, downstream gates could
validate different bytes than the producer meant, confuse mutable locators with
immutable content, or require a second migration wave.

## Decision

Adopt a canonical schema registry, algorithm-agile `DigestRef`, and one declared
canonical JSON profile.

New schemas use `DigestRef` with `algorithm` and `value`. Legacy `*_sha256`
names are migration aliases only; new fields use `*_digest`. Authority-root
hashes use explicit domain separation:

```text
hash("conveyor:<root-kind>:v<version>\0" || canonical_root_manifest_bytes)
```

Canonical JSON uses `rfc8785-jcs` unless superseded by a later ADR.
JCS-authoritative schemas must encode ambiguous values safely: money as integer
minor units plus currency, large integers as decimal strings outside safe I-JSON
range, timestamps as normalized RFC3339 strings, durations as integer
milliseconds or nanoseconds, and unordered sets as deterministically sorted
arrays.

Every authority-bearing, evidence-bearing, or policy-addressable object uses
`ResourceRef` or `SubjectRef` rather than bespoke `*_id` plus `*_kind` pairs,
unless a migration adapter maps the legacy shape losslessly. A reference with a
digest is immutable and content-addressed; a reference without a digest is a
mutable locator and cannot by itself grant authority.

`SchemaRegistryEntry` is the canonical schema registry record. Every artifact
carries both schema version and schema digest. Writers emit only current
versions; readers declare supported versions. Breaking changes require migration
or an explicit unsupported verdict.

## Consequences

All gate, policy, comparison, invalidation, approval, migration, and offline
verification code must resolve human-friendly identifiers to canonical
references before authority evaluation. Artifact migrations preserve original
bytes, emit migrated artifacts with lineage, and never rewrite history.

Changing canonicalization, digest shape, shared vocabularies, or schema registry
semantics is migration-heavy and must be treated as a new architectural
decision.

## Implementation Notes

P15-A1 must deliver `CAPABILITY-REGISTRY.md` with legacy aliases, a
machine-readable schema registry, shared vocabularies, the canonical JSON
profile, `DigestRef`, artifact schema migration framework, and
migrated/projection adapters for Phase-1 evidence.

`SchemaRegistryEntry` includes schema key, schema id, schema version, schema
digest, dialect, canonicalization profile, compatibility classification, reader
support, writer status, migration sources, and owner.

Shared enum vocabularies are registered once. New tickets, ADRs, schemas, and
implementation artifacts should use canonical capability keys, not ambiguous
legacy `Cxx` identifiers alone.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md,
  sections 0.2 corrections A and L, 1.3, 5.1, 18.1 P15-A1, 21, and 28.2 item 4.
