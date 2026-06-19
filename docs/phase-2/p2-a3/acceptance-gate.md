# P2-A3 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Work dependency graph, interface readiness graph, decision-block graph,
preliminary verification obligations, ArtifactInput derivation index, graph
analyses, structural dry-run, impact preview, and graph resource schemas.

## Exit Criteria

### likely-file overlap does not create a hard work edge

Evidence:

- `Conveyor.Planning.SliceDependency` materializes only `execution_hard` and
  `integration_order` edges.
- `PlanningSliceDependencyTest` proves likely overlap and interface readiness
  are ignored as work-edge kinds and remain scheduling hints only.

### provider/consumer schemas/versions resolve or block

Evidence:

- `Conveyor.Planning.InterfaceGraph` resolves InterfaceContracts and
  SliceInterfaceBindings separately from the work graph.
- `PlanningInterfaceGraphTest` proves compatible consumers become ready, while
  missing providers and incompatible version ranges block.

### a human decision is not encoded as a fake Slice edge

Evidence:

- `Conveyor.Planning.SliceDecisionBlock` evaluates HumanDecision state in a
  decision graph and always emits `fake_work_edges: []`.
- `PlanningSliceDecisionBlockTest` proves unresolved/missing decisions block
  Slice readiness without creating work dependencies.

### an unsafe atomicity split is rejected

Evidence:

- `Conveyor.Planning.GraphAnalyses` checks atomicity group membership and emits
  blocking findings for missing members.
- `PlanningGraphAnalysesTest` proves broken atomicity groups are rejected.

### every authority artifact has derivation inputs

Evidence:

- `Conveyor.Planning.ArtifactInputIndex` emits schema-shaped ArtifactInput rows
  with semantic, authority, evidence, advisory, and presentation roles.
- `PlanningArtifactInputIndexTest` proves emitted artifacts retain queryable
  derivation inputs and unknown semantic/advisory ambiguity fails closed to
  semantic invalidation.

### low impact confidence fails wide

Evidence:

- `Conveyor.Planning.StructuralDryRun.preview_impact/3` returns
  `status: :fail_wide` when derivation confidence is below threshold.
- `PlanningStructuralDryRunTest` proves low-confidence previews affect every
  known artifact instead of narrowing unsafely.

### structural simulation uses no fabricated economics

Evidence:

- `Conveyor.Planning.StructuralDryRun` computes waves, fan-in/out, critical
  path, and conflict-domain hints, but reports cost/time as
  `:insufficient_history`.
- `PlanningStructuralDryRunTest` proves structural simulation does not invent
  calibrated economics.

## Schema Evidence

- `conveyor.slice_dependency@1` records execution/integration work edges.
- `conveyor.interface_contract@1` records interface authority boundaries.
- `conveyor.slice_interface_binding@1` records provides/requires/modifies
  relationships.
- `conveyor.slice_decision_block@1` records HumanDecision-backed Slice blocks.
- `EvidenceKernelResourcesTest` validates all four schemas against valid and
  missing-schema-version invalid examples and proves they are registered.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `PlanningSliceDependencyTest` | likely overlap as hard edge, interface readiness as work edge, work graph cycle, unreachable active node | none |
| `PlanningInterfaceGraphTest` | missing provider, incompatible consumer version, interface readiness converted to work edges | none |
| `PlanningSliceDecisionBlockTest` | missing/unresolved HumanDecision, fake Slice edge for decision block | none |
| `PlanningPreliminaryVerificationTest` | orphan AC fabricating an obligation, missing protected policy obligation | none |
| `PlanningArtifactInputIndexTest` | missing role policy, unsafe narrow invalidation for unknown semantic/advisory role | none |
| `PlanningGraphAnalysesTest` | broken atomicity, unapproved scope, traceability gaps, confetti slices, false parallelism, oracle infeasibility | none |
| `PlanningStructuralDryRunTest` | fabricated economics, low-confidence narrow impact preview | none |
| `conveyor.slice_dependency@1` | missing schema version and unregistered schema resource | none |
| `conveyor.interface_contract@1` | missing schema version and unregistered schema resource | none |
| `conveyor.slice_interface_binding@1` | missing schema version and unregistered schema resource | none |
| `conveyor.slice_decision_block@1` | missing schema version and unregistered schema resource | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the P2-A3 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
