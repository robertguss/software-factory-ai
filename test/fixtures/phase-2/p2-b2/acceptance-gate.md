# P2-B2 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: independent Test Architect workspace, TestSpecification/TestPack patch
and challenge artifacts, falsifier preservation, oracle-feasibility
classification, integrity/Sentinel gate integration, honest human verification,
and dimensional ContractAudit reporting.

## Exit Criteria

### the Test Architect cannot edit source

Evidence:

- `Conveyor.TestArchitect.Workspace` emits a read-only source mount and isolated
  read-write test workspace.
- `TestArchitectWorkspaceTest` proves source writes and mount escapes are
  blocking findings, while command normalization gives write access only to the
  test workspace.

### tests map to obligations/ACs and base reasons

Evidence:

- `Conveyor.TestArchitect.Artifacts` builds schema-valid `TestSpecification`,
  `TestPackPatch`, and `ChallengeCase` artifacts.
- `TestArchitectArtifactsTest` proves each TestSpecification maps to
  VerificationObligations and ACs, carries expected base/candidate behavior,
  expected base reason, result adapter, environment policy, and nondeterminism
  policy.

### a dropped falsifier blocks

Evidence:

- `Conveyor.TestArchitect.FalsifierPreservation` translates compiler-derived
  falsifier seeds through TestSpecifications or records explicit supersession.
- `TestArchitectFalsifierPreservationTest` proves translated and superseded
  seeds satisfy the report, while a dropped seed remains a blocking
  `falsifier_seed.dropped` finding.

### `boundary_unclear` routes to split/clarify

Evidence:

- `Conveyor.TestArchitect.OracleFeasibility` classifies oracle paths as
  automatable, partially automatable, boundary unclear, or not automatable.
- `OracleFeasibilityTest` proves `boundary_unclear` returns
  `route: split_or_clarify`, `autonomy_cap: blocked`, and a blocking finding
  instead of retrying the same vague Slice.

### universal mutation is required only with a legitimate reference

Evidence:

- `Conveyor.TestArchitect.IntegrityGate` integrates the hard Test-Integrity
  Sentinel verdict with per-obligation EvidenceRequirement satisfaction.
- `TestArchitectIntegrityGateTest` proves uncalibrated
  `universal_mutation_without_reference` and `dynamic_coverage` checks are
  advisory findings only and never hard-block authority.

### human-only evidence remains human-only

Evidence:

- `Conveyor.TestArchitect.HumanVerification` creates an explicit
  `human_verification_procedure` with
  `required_evidence_kind: human_observation`, `machine_promotable: false`, and
  `max_autonomy: observe_only`.
- `HumanVerificationTest` proves accepted observations emit
  `VerificationEvidence` with `producer_kind: human_observer` and
  `evidence_kind: human_observation`, and that promotion to machine evidence is
  rejected.

### weak evidence routes to its author, not the implementer

Evidence:

- `Conveyor.TestArchitect.HumanVerification` records the weak-evidence route on
  the procedure.
- `HumanVerificationTest` proves suspect human evidence routes to the Test
  Architect author and explicitly not to the implementer.

## Contract Quality Evidence

- `Conveyor.TestArchitect.ContractAudit` emits schema-valid
  `conveyor.contract_audit@1` reports.
- `ContractAuditTest` proves ContractAudit remains dimensional per stage and
  quality dimension, with no opaque aggregate score.

## Release Report

| Evidence source                          | Failed cases represented                                                                                                            | Excluded cases |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| `TestArchitectWorkspaceTest`             | source-write attempts, mount escapes, command write roots outside the test workspace                                                | none           |
| `TestArchitectArtifactsTest`             | tests without obligation/AC mappings, missing base reasons, schema/registry drift for TestSpecification/TestPackPatch/ChallengeCase | none           |
| `TestArchitectFalsifierPreservationTest` | dropped compiler falsifier seeds, missing explicit supersession                                                                     | none           |
| `OracleFeasibilityTest`                  | vague boundary retry, human-only oracle mislabeled as ordinary automation                                                           | none           |
| `TestArchitectIntegrityGateTest`         | untrustworthy Sentinel runs, unsatisfied obligations, advisory mutation/coverage becoming hard blockers                             | none           |
| `HumanVerificationTest`                  | human evidence promoted as machine evidence, weak evidence routed to implementer                                                    | none           |
| `ContractAuditTest`                      | ContractAudit schema drift, opaque aggregate scoring                                                                                | none           |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B2 Test Architect test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
