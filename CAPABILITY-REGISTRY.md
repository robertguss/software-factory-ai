# Conveyor Capability Registry

Status: accepted

Date: 2026-06-19

This registry defines stable semantic `capability_key` values. Legacy `C11`
through `C20` labels are retained only as provenance aliases for older planning
documents. New schemas, ADRs, issues, commits, and UI labels should use the
canonical keys below.

| Capability key | Legacy aliases | Scope |
| --- | --- | --- |
| `SCHEMA-REGISTRY` | `C11` | Versioned schema identity, shared vocabularies, reader/writer support, compatibility declarations, and migration lineage. |
| `ATTESTATION-ENVELOPES` | `C12` | In-toto statement envelopes, local verification, subject digest checks, and signature-status policy. |
| `DIGEST-IDENTITY` | `C13` | Algorithm-agile `DigestRef`, canonical JSON profile, and domain-separated authority-root hashing. |
| `REFERENCE-IDENTITY` | `C14` | Canonical `ResourceRef` and `SubjectRef` shapes for authority, evidence, and policy-addressable objects. |
| `LIFECYCLE-CONTRACTS` | `C15` | Declarative mutable-resource state machines whose transitions cite policy, authority inputs, and events. |
| `ROOT-MANIFESTS` | `C16` | Domain-separated manifests for shared authority, epic authority, review, archive, and evidence roots. |
| `EVIDENCE-PROJECTION` | `C17` | Phase-1 evidence projection under the schema registry without rewriting original artifact bytes. |
| `POLICY-DECISIONS` | `C18` | Typed policy decision contracts, stable reason codes, and fail-closed indeterminate handling. |
| `TOOL-CONTRACTS` | `C19` | Typed tool authority, host authorization, and role-visible input/output validation. |
| `ROLE-VIEWS` | `C20` | Policy-compiled role views that separate instruction authority from untrusted content. |

## Versioning

Registry rows are append-only within a major program phase. A capability key can
gain narrower sub-capabilities, but its meaning cannot be silently reused for a
different authority surface. Renames require an alias row and a migration note.

## Content Addressing

When a capability governs an artifact schema or authority root, consumers should
cite both the `capability_key` and the relevant schema or root `DigestRef`.
Human-friendly aliases are acceptable in prose only when the canonical key is
also present.
