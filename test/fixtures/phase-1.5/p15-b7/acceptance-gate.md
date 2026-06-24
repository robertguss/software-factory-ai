# P15-B7 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Live predeclared sampling, frozen success bands, optional secondary
confirmation, measurement studies, labelled context ground truth, unlabelled
context proxies, and Tutor/retry-escalation shadow controls.

## Exit Criteria

### no rerun-until-green binary live gate

Evidence:

- `Conveyor.Battery.LiveSampling` runs the selected predeclared live cases once
  for the requested grant scopes and records `rerun_until_green: false`.
- `BatteryLiveSamplingTest` proves selected cases are sampled exactly once and
  that the report never upgrades live sampling into a rerun-until-green binary
  release gate.
- `RunBatteryTest` remains the deterministic execution boundary for each case
  result instead of a loop that retries until the aggregate turns green.

### statistical method/threshold/budget frozen before samples

Evidence:

- `Conveyor.Battery.SamplingPolicy` canonicalizes and digests the predeclared
  sample policy before live samples are run.
- `BatterySamplingPolicyTest` proves the policy digest changes when the
  statistical method, threshold, or budget changes.
- `BatteryLiveSamplingTest` proves each live sampling report retains the frozen
  `SamplingPolicy` digest and quality-floor inputs used for the run.

### insufficient evidence remains not assessed

Evidence:

- `Conveyor.Battery.LiveSampling` reports `band_status: "not_assessed"` when a
  required stratum has fewer samples than the frozen policy requires.
- `BatteryLiveSamplingTest` proves insufficient live evidence remains explicitly
  not assessed rather than passing or failing by implication.
- `RunBatteryTest` preserves case-level outcomes so missing samples cannot be
  collapsed into a successful aggregate.

### safety failure cannot be averaged away

Evidence:

- `Conveyor.Battery.LiveSampling` counts safety violations separately from
  quality scores and lets `safety_failed` dominate quality-band averages.
- `BatteryLiveSamplingTest` proves a safety violation fails the stratum even
  when other sampled cases have acceptable quality scores.
- `RunBatteryTest` keeps safety invariant failures as case results, not advisory
  scoring metadata.

### secondary-provider outage does not invalidate the core deterministic build

Evidence:

- `Conveyor.Battery.SecondaryConfirmation` is explicitly
  `non_gating_confirmation` and records `invalidates_core_build: false`.
- `BatterySecondaryConfirmationTest` proves an unavailable secondary adapter
  returns `secondary_unavailable` without invalidating the deterministic primary
  build.
- `BatteryLiveSamplingTest` remains the primary live-sampling gate and does not
  depend on a secondary provider result.

### null/negative studies are retained

Evidence:

- `Conveyor.Battery.MeasurementStudy` retains every adapter, AGENTS.md, prompt,
  scout, and Tutor study outcome, including null and negative results.
- `BatteryMeasurementStudyTest` proves null and negative outcomes are counted,
  marked `retention: "retained"`, and included in the stable study digest.
- `EvalSuitesTest` keeps the measurement-study surface tied to the evaluation
  suite metadata rather than filtering only favorable outcomes.

### Tutor cannot close work; contract/policy faults do not consume escalation

Evidence:

- `Conveyor.ShadowControls.tutor_advice/1` marks Tutor output advisory-only,
  unable to close a slice or satisfy a verification obligation.
- `ShadowControlsTest` proves Tutor advice carries no authority effect and
  cannot close work.
- `Conveyor.ShadowControls.retry_escalation/1` consumes escalation tiers for
  implementation and validation failures, while contract, policy, adapter, and
  infrastructure faults route without escalation.
- `ShadowControlsTest` proves contract and policy faults do not consume retry
  escalation.

## Context Ground Truth Evidence

- `Conveyor.ContextGroundTruth` reports precision and recall only for labelled
  cases that carry `conveyor.context_ground_truth@1` style necessary, useful,
  and forbidden source references.
- `ContextGroundTruthTest` proves labelled cases report selected-context
  precision and necessary-context recall, while unlabelled cases report only
  named proxies such as unused opened files, missing context after failure, and
  critical context shedding.
- `conveyor.context_ground_truth@1` is registered as a P15-B7 current schema and
  validated by `EvidenceKernelResourcesTest`.

## Release Report

| Evidence source                    | Failed cases represented                                                                                    | Excluded cases |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------- | -------------- |
| `BatteryLiveSamplingTest`          | rerun-until-green attempts, missing frozen policy digest, insufficient samples, safety violation laundering | none           |
| `BatterySamplingPolicyTest`        | changed sample policy digest, unfrozen method/threshold/budget                                              | none           |
| `RunBatteryTest`                   | case execution failures and case-level outcome preservation                                                 | none           |
| `BatterySecondaryConfirmationTest` | same-adapter confirmation, unavailable secondary provider, mismatched representative result                 | none           |
| `BatteryMeasurementStudyTest`      | dropped null result, dropped negative result, unstable study digest                                         | none           |
| `ContextGroundTruthTest`           | missing labelled precision/recall, forbidden context selection, unlabelled proxy confusion                  | none           |
| `ShadowControlsTest`               | Tutor closing work, Tutor satisfying obligations, contract/policy faults consuming escalation               | none           |
| `conveyor.context_ground_truth@1`  | missing schema version and unregistered schema resource                                                     | none           |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the B7 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
