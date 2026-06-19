# P15-A1 Acceptance Gate

Status: passed

Date: 2026-06-19

## Exit Criteria

| Criterion | Evidence |
| --- | --- |
| No new ticket, ADR, or schema uses ambiguous `Cxx` alone. | `CAPABILITY-REGISTRY.md` defines canonical capability keys and keeps `C11` through `C20` only as legacy aliases. |
| Every new artifact carries schema version, digest, and canonicalization profile. | `docs/schemas/registry.json` declares `canonicalization_profile`; `docs/schemas/conveyor.schema_registry_entry@1.json` requires `digest` and `canonicalization_profile`; all P15-A1 schemas require `schema_version`. |
| Frozen old artifacts validate or fail explicitly. | `docs/phase-1.5/p15-a1/phase-1-evidence-projection.md` maps each frozen Phase 1 artifact family to a registered schema and requires explicit validation failure. |
| Breaking schema changes require a migration. | `docs/schemas/MIGRATIONS.md` defines `breaking` compatibility and requires old artifact bytes, migrated artifact, semantic-equivalence report, and lineage. |
| Attestation subject-digest mismatch fails. | `docs/schemas/ATTESTATIONS.md` lists subject digest mismatch as fail-closed; `conveyor.attestation_statement@1` requires subject digests. |
| Migration preserves original bytes and emits new lineage, never rewrites. | `docs/schemas/MIGRATIONS.md` and `phase-1-evidence-projection.md` both require original bytes and separate projection lineage. |

## Verification

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); Code.require_file("test/conveyor/schema_registry_resources_test.exs"); result = ExUnit.run(); if result.failures > 0, do: System.halt(1), else: System.halt(0)'`
- Registry/doc verifier confirmed eight schema entries, eleven shared vocabularies, and accepted status on support docs.
- ASCII scan and `git diff --check` passed for the P15-A1 artifacts.

## Gate Result

P15-A1 is accepted for local progression into P15-A2. The accepted scope is a
local schema registry and documentation-backed projection framework; later beads
still own runtime migration adapters, policy decisions, ToolContracts, and
RoleViews.
