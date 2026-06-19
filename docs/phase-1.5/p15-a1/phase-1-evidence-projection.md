# Phase 1 Evidence Projection Under Registry

Status: accepted

Date: 2026-06-19

## Source Baseline

Projection starts from
`docs/phase-1.5/p15-a0/phase-1-baseline-freeze.json`. Original Phase 1 artifact
bytes remain immutable. Projection creates registry-aware lineage instead of
editing existing artifacts.

## Registry Mapping

| Artifact family | Registered schema or seam |
| --- | --- |
| Plan contracts | `conveyor.plan@1` |
| Run specs | `conveyor.run_spec@1` |
| Station plans | `conveyor.station_plan@1` |
| Evidence packets | `conveyor.evidence@1` |
| Reviews | `conveyor.review@1` |
| Gate results | `conveyor.gate@1` |
| Run bundles | `conveyor.run_bundle@1` |
| Phase branch decisions | `conveyor.phase_next_decision@1` |

## Projection Rules

- Validate against the registered schema or fail explicitly.
- Convert legacy `*_sha256` prose references into `DigestRef` lineage notes
  without mutating the original artifact.
- Add `ResourceRef` and `SubjectRef` wrappers only in projected lineage records.
- Emit an attestation statement for projected authority-bearing evidence.
- Preserve original artifact digests and projection digests separately.

## Acceptance

The current projection is documentation-backed rather than a runtime migrator.
It is locally complete when the schema registry, shared vocabularies,
canonicalization profile, migration rules, attestation envelope, and baseline
mapping all exist and cross-reference the frozen Phase 1 baseline.
