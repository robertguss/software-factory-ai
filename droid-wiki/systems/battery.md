# Battery

The battery system in `lib/conveyor/battery/` collects live statistical quality
signals. It runs predeclared sampling policies against real adapter executions,
records measurement studies, performs optional secondary confirmation across
materially different providers, and produces release-facing reports. The battery
is the empirical complement to the deterministic gate: where the gate checks one
run, the battery estimates how the system behaves across many.

## LiveSampling

`lib/conveyor/battery/live_sampling.ex` executes predeclared live Battery
samples for requested grant-scope strata. This module does not decide grant
issuance. It preserves the frozen `SamplingPolicy` digest, runs the selected
predeclared cases once through the existing Battery runner, and records observed
misses as measurement data.

The `run!/3` function filters cases by requested grant scopes, runs them through
`RunBattery.run!`, and computes stratum results per requested scope. Each
stratum result carries the scope key, case count, miss count, and stratum result
(`quality_floor_met`, `miss_observed`, or `quality_floor_not_met`). The worst
required stratum result is derived for the overall run.

Provider or infrastructure failures are counted separately from quality misses,
so an adapter outage does not get misread as a quality signal.

## MeasurementStudy

`lib/conveyor/battery/measurement_study.ex` is the controlled measurement-study
reporter for Battery ablations. Studies are measured against a frozen input
digest so comparisons are fair. Five dimensions are allowed: adapter, agents_md,
prompt, scout, and tutor.

Negative and null results are first-class retained evidence so ablations cannot
be quietly cherry-picked. The report carries the study id, frozen input digest,
covered dimensions, negative result count, null result count, and per-variant
results (variant id, dimension, outcome, metric delta, retention status). The
report is content-addressed with a study digest.

## ReleaseReport

`lib/conveyor/battery/release_report.ex` is the canonical release report
projection. Source summaries are advisory text; failed and excluded cases remain
structured fields so summaries cannot hide canonical blockers. The report
carries the schema version, completeness flag, source count, per-source
summaries with failed and excluded cases, and flattened canonical blockers and
excluded cases across all sources.

## SamplingPolicy

`lib/conveyor/battery/sampling_policy.ex` builds predeclared, content-addressed
Battery sampling policies. The `predeclare!/1` function validates 11 required
fields: method, min samples, max samples, confidence, floor P0, stopping rule,
sampling unit, cluster key, max samples per cluster, strata, and sequential
validity. The sampling unit must be `repository_case_cluster`, and min samples
cannot exceed max samples. The policy is content-addressed with a
`policy_digest` over canonical JSON.

## SecondaryConfirmation

`lib/conveyor/battery/secondary_confirmation.ex` performs optional secondary
live-adapter confirmation. The secondary adapter can add confidence that the
abstraction behaves across a materially different provider path, but its result
is non-gating: outages and mismatches are recorded without replacing the
deterministic primary oracle.

The `run!/3` function validates that the secondary adapter differs from the
primary, selects representative cases, runs them, and reports the confirmation
status. Declared representative cases absent from the manifest are reported as
missing, not silently dropped. The result explicitly declares
`invalidates_core_build: false` and
`core_build_oracle: deterministic_primary_unchanged`.

## TraceAssertions

`lib/conveyor/battery/trace_assertions.ex` evaluates Battery trace assertions
against canonical events and effect receipts. Assertions specify a source
(`event` or `effect_receipt`), a match (field and equals), and an operator
(`never`, `eventually`, `always`, `bounded_count`). The `evaluate/2` function
matches records against assertions and produces pass/fail results with observed
counts, matching record ids, and failure reasons. Unknown operators fail cleanly
rather than crashing the evaluation.

## FixtureBoundary

`lib/conveyor/battery/fixture_boundary.ex` keeps role-visible Battery fixture
data separate from scorer-only material. The `split!/1` function partitions a
fixture into a `role_safe_case` and a `scorer_only_sidecar`, with the
scorer-only sidecar tagged with a `restricted_evaluation` information label and
a `secure_evaluation` storage scope. The `scan_role_visible/2` function scans
role-visible data for `secure-eval://` references and restricted evaluation
labels, returning findings if scorer-only material leaks into role-visible
fields.

## Key source files

| File                                             | Purpose                                                                        |
| ------------------------------------------------ | ------------------------------------------------------------------------------ |
| `lib/conveyor/battery/live_sampling.ex`          | Executes predeclared live samples for requested grant-scope strata.            |
| `lib/conveyor/battery/measurement_study.ex`      | Controlled measurement-study reporter with retained negative and null results. |
| `lib/conveyor/battery/release_report.ex`         | Canonical release report projection with structured blockers.                  |
| `lib/conveyor/battery/sampling_policy.ex`        | Predeclared, content-addressed sampling policy builder.                        |
| `lib/conveyor/battery/secondary_confirmation.ex` | Optional non-gating secondary live-adapter confirmation.                       |
| `lib/conveyor/battery/trace_assertions.ex`       | Evaluates trace assertions against canonical events and effect receipts.       |
| `lib/conveyor/battery/fixture_boundary.ex`       | Separates role-visible fixture data from scorer-only material.                 |

## Related pages

- [Qualification](qualification.md) — grants use battery quality intervals
- [Agent runner](agent-runner.md) — adapters that battery samples execute
- [Cassettes](cassettes.md) — recording and replay of battery runs
- [Architecture](../overview/architecture.md) — Oban workers including
  `RunBattery`
