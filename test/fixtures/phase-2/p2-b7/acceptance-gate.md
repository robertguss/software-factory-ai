# P2-B7 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: pre-registered pilot plan, immutable PilotSelection, serial execution
metrics, and retrospective/Chronicle reporting for the generated-plan pilot.

## Exit Criteria

### no selected contract is rewritten from scratch just to pass

Evidence:

- `Conveyor.Planning.PilotRetrospective` treats a from-scratch manual contract
  rewrite counted as generated success as a release failure.
- `PlanningPilotRetrospectiveTest` proves a selected contract edit with
  `reconstruction_kind: from_scratch` cannot be recorded as success.

### the selected set never changes after outcomes

Evidence:

- `Conveyor.Planning.PilotSelection` freezes `conveyor.pilot_selection@1` before
  implementation starts, with deterministic policy and selection digests.
- `PlanningPilotSelectionTest` proves selection is blocked once implementation
  has started.
- `Conveyor.Planning.PilotRetrospective` compares the frozen selected set with
  the final selected set.
- `PlanningPilotRetrospectiveTest` proves selected-set drift after outcomes is
  reported as release failure.

### no failed selection is replaced

Evidence:

- `Conveyor.Planning.PilotRetrospective` records any replacement attempt for a
  failed selected Slice as `failed_selection_replaced`.
- `PlanningPilotRetrospectiveTest` proves a failed Slice cannot be replaced with
  an easier final Slice.

### every failure gets typed comparison/diagnosis/recovery

Evidence:

- `Conveyor.Planning.PilotRetrospective` requires every failure record to carry
  comparison, diagnosis, and recovery refs.
- `PlanningPilotRetrospectiveTest` proves failures are typed and reported with
  complete comparison/diagnosis/recovery links.

### unrelated ready Slices continue when one is parked

Evidence:

- `test/fixtures/phase-2/p2-b7/pilot-plan.json` includes a parked/disputed path
  and a terminal Chronicle Slice that depends on both the parked path and
  unrelated amendment path.
- `PlanningPilotPlanTest` proves the parked path is present in the 10-Slice
  multi-Epic pilot.
- `Conveyor.Planning.PilotExecution` summarizes parked Slice execution without
  breaking the serial order of later selected Slices.
- `PlanningPilotExecutionTest` proves a parked Slice can coexist with later
  recovered/passed Slice events.

### the final report separates plan/compiler/context/implementation/evidence/adapter/operator failures

Evidence:

- `Conveyor.Planning.PilotRetrospective` emits a Chronicle with dedicated
  sections for plan, compiler, context, implementation, evidence, adapter, and
  operator failures.
- `PlanningPilotRetrospectiveTest` proves compiler and context failures are
  separated in the rendered Chronicle and counted by class.

### the pilot covers graph/interface/risk/human-verification classes

Evidence:

- `test/fixtures/phase-2/p2-b7/pilot-plan.json` defines a 10-Slice multi-Epic
  plan with fork/join, public interface provider/consumer, migration
  compatibility, ambiguity, alternative candidate, amendment path, parked path,
  and a human-verification-only obligation.
- `PlanningPilotPlanTest` proves the plan has 8-12 Slices, multiple Epics, valid
  dependencies, and all required coverage classes.
- `Conveyor.Planning.PilotSelection` selects every machine-executable Slice for
  this <=12-Slice pilot and records the required coverage classes.
- `PlanningPilotSelectionTest` proves the frozen selection is schema-valid.
- `PilotSelectionSchemaTest` proves `conveyor.pilot_selection@1` requires the
  immutable `selection_digest` and is registered as the current P2-B7 schema.

## Release Report

| Evidence source                  | Failed cases represented                                                                                                 | Excluded cases |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | -------------- |
| `PlanningPilotPlanTest`          | missing coverage class, invalid dependency, wrong slice count                                                            | none           |
| `PilotSelectionSchemaTest`       | missing selection digest, missing registry row                                                                           | none           |
| `PlanningPilotSelectionTest`     | selection after implementation start, missing machine-executable slices                                                  | none           |
| `PlanningPilotExecutionTest`     | implementation width > 1, missing pilot metrics                                                                          | none           |
| `PlanningPilotRetrospectiveTest` | selected-set drift, failed replacement, from-scratch manual rewrite counted as success, missing failure-class separation | none           |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B7 test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `jq empty` for the PilotSelection schema/examples and pilot plan fixture.
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
