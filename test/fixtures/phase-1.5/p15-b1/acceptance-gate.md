# P15-B1 Acceptance Gate

Status: pass.

## Evidence

| Exit criterion | Evidence |
| --- | --- |
| fixture validation precedes provider calls | `RunBatteryTest` covers the poison pill path and fails the test if the injected agent runner is called for malformed fixtures. `FixtureBoundary.split!/1` also scans role-safe fixture data before returning it. |
| poison pill yields `battery_fixture_failure` | `RunBatteryTest` asserts `trap_runner_honesty` emits a `battery_fixture_failure` sample with fixture failure class and no run attempts. `BatteryCorpusManifestTest` pins the `trap_runner_honesty` corpus entry. |
| safety-trajectory violations are detected even when the terminal outcome is safe | `BatteryTraceAssertionsTest` covers `never`, `always`, `eventually`, and `bounded_count`; `RunBatteryTest` proves a hidden-oracle trace fails a sample even when terminal outcome matches. |
| failed samples cannot be omitted/replaced | `RunBatteryTest` keeps provider failure samples in `sample_results` and preserves the declared sample count in the aggregate result. |
| scorer-only metadata never reaches RoleViews/prompts/workspaces/projections | `BatteryFixtureBoundaryTest` splits role-safe data from scorer-only sidecars, marks scorer-only records `restricted_evaluation`, rejects `secure-eval://` references, and rejects `restricted_evaluation` labels in role-visible exports. |
| threshold/stop-rule change creates a new policy digest | `BatterySamplingPolicyTest` recomputes content-addressed `SamplingPolicy` digests and proves floor or stop-rule changes produce a new digest. |
| provider/infra failures are separated from quality | `RunBatteryTest` records provider failures as `:provider_failure` with `[:provider]`, and terminal outcome mismatches as `[:quality]`. |

## Artifacts

- `test/fixtures/phase-1.5/p15-b1/battery-corpus.json`
- `test/fixtures/phase-1.5/p15-b1/sampling-policy.json`
- `lib/conveyor/battery/trace_assertions.ex`
- `lib/conveyor/battery/fixture_boundary.ex`
- `lib/conveyor/battery/sampling_policy.ex`
- `lib/conveyor/jobs/run_battery.ex`

## Verification

- `BatteryFixtureBoundaryTest`
- `BatteryTraceAssertionsTest`
- `BatteryCorpusManifestTest`
- `BatterySamplingPolicyTest`
- `RunBatteryTest`
- `MIX_ENV=test mix compile --warnings-as-errors`
