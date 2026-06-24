# P2-B8 Release Suite Report

Status: available DB-free release suites passed locally; full DB-backed
`mix test` is blocked before test execution by PostgreSQL authentication.

Scope: contract/security/property/replay/recovery/retention/legibility checks
for the P2-B Contract Foundry release gate.

## Hard Correctness Invariants

| Invariant                           | Local evidence                                                                                                                                          |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 100% traceability                   | `ContractAuditTest`, `PlanningStaticCompilerAcceptanceGateTest`, and prior P2-B acceptance gates cover traceability contracts and static report parity. |
| no orphans                          | `PlanningStaticCompilerAcceptanceGateTest` and the release suite exercise structural orphan detection through compiler/static checks.                   |
| no cycles                           | `br dep cycles --json` returned `{"cycles":[],"count":0,...}` for the active bead graph.                                                                |
| no unresolved hard constraint       | `PlanningCompilerPropertiesTest` and prior planning acceptance gates cover hard-constraint failures as blocking findings.                               |
| provenance for every scope addition | `ContractAuditTest` and static compiler checks cover source-anchor and traceability provenance.                                                         |
| reproducible roots                  | `PlanningStaticCompilerAcceptanceGateTest` covers reproducible static roots and bundle parity.                                                          |
| exact approval binding              | prior P2-B5 evidence and focused release checks include hierarchical approval binding behavior.                                                         |
| no in-place mutation                | prior P2-B6 evidence covers amendment revisioning and selective invalidation without in-place mutation.                                                 |
| role isolation                      | `ContractAuthorTest` and contract forge checks cover role-owned author/reviewer obligations.                                                            |
| no injection escape                 | `GateStagesPolicySecretTest` and `Sandbox.NetworkPolicyTest` cover policy/secret and network boundaries.                                                |
| honest human verification           | `PlanningPilotAcceptanceGateTest` and prior P2-B2 evidence cover human-only verification as explicit human evidence.                                    |
| no UI/static/CLI disagreement       | `PlanningWorkbenchAcceptanceGateTest` and `PlanningStaticCompilerAcceptanceGateTest` cover static/workbench parity.                                     |

## Suite Classes

| Suite class | Evidence files                                                                                                                                                                |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| contract    | `ContractAuditTest`, `ContractAuthorTest`, `ContractForgeAcceptanceGateTest`                                                                                                  |
| security    | `GateStagesPolicySecretTest`, `Sandbox.NetworkPolicyTest`                                                                                                                     |
| property    | `PlanningCompilerPropertiesTest`                                                                                                                                              |
| replay      | `CassetteReplayEngineTest`, `CassetteReplayDiagnosticsTest`, `CassetteFreshnessTest`                                                                                          |
| recovery    | `RecoveryTest`, `Recovery.HonestyEvalTest`, `FailureDiagnosisTest`                                                                                                            |
| retention   | `BatteryMeasurementStudyTest` retains stable measurement-study samples; schema registry coverage includes retained/audit-class artifacts.                                     |
| legibility  | `PlanningWorkbenchAcceptanceGateTest`, `PlanningStaticCompilerAcceptanceGateTest`, and `PlanningPilotAcceptanceGateTest` cover report, workbench, and pilot-gate readability. |

## Commands

### Focused release suite

Command:

```sh
MIX_ENV=test mix run --no-start -e 'ExUnit.start(); Enum.each([...], &Code.require_file/1); result = ExUnit.run(); if result.failures > 0, do: System.halt(1), else: System.halt(0)'
```

Expanded test files:

- `test/conveyor/contract_audit_test.exs`
- `test/conveyor/contract_author_test.exs`
- `test/conveyor/contract_forge_acceptance_gate_test.exs`
- `test/conveyor/planning_compiler_properties_test.exs`
- `test/conveyor/gate_stages_policy_secret_test.exs`
- `test/conveyor/sandbox/network_policy_test.exs`
- `test/conveyor/cassette_replay_engine_test.exs`
- `test/conveyor/cassette_replay_diagnostics_test.exs`
- `test/conveyor/cassette_freshness_test.exs`
- `test/conveyor/recovery_test.exs`
- `test/conveyor/recovery_honesty_eval_test.exs`
- `test/conveyor/failure_diagnosis_test.exs`
- `test/conveyor/battery_measurement_study_test.exs`
- `test/conveyor/planning_static_compiler_acceptance_gate_test.exs`
- `test/conveyor/planning_workbench_acceptance_gate_test.exs`
- `test/conveyor/planning_pilot_acceptance_gate_test.exs`

Outcome: passed locally with `42 passed (2 properties, 40 tests)`.

### Compile

Command:

```sh
MIX_ENV=test mix compile --warnings-as-errors
```

Outcome: passed locally with no compiler output.

### Dependency graph

Command:

```sh
br dep cycles --json
```

Outcome:

```json
{
  "cycles": [],
  "count": 0,
  "active_count": 0,
  "archived_closed_count": 0,
  "total_count": 0,
  "blocking_only": false,
  "include_closed": false,
  "scope": "active"
}
```

### Full DB-backed suite

Command:

```sh
MIX_ENV=test mix test
```

Outcome: blocked before test execution by local PostgreSQL authentication:

```text
Postgrex.Error FATAL 28P01 (invalid_password) password authentication failed for user "postgres"
** (Mix) The database for Conveyor.Repo couldn't be created: killed
```

This is an environment blocker for DB-backed tests, not a passing release-suite
signal.
