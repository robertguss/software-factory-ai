# P15-B6 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Evidence Time Machine comparison, stale/diff commands, immutable
diagnosis, typed recovery, safe automatic action policy, honesty metrics, and
deterministic invalidation preview.

## Exit Criteria

### weakening/freshness/root/grant changes classify materially

Evidence:

- `Conveyor.Evidence.Comparator` preserves all materiality labels and derives a
  deterministic dominant label.
- `EvidenceComparatorTest` proves materially relevant labels such as policy,
  approval, grant, scope, environment, and capability changes produce
  `materially_different` summaries instead of collapsing to cosmetic changes.
- `ConveyorEvidenceTimeMachineTest` proves the run/plan/artifact/grant diff and
  `why_stale` commands expose the same canonical comparison data through the CLI
  projection.

### missing/erased/tampered evidence yields `incomparable`

Evidence:

- `Conveyor.Evidence.Comparator` converts unavailable, unauthorized, erased, or
  digest-mismatched subjects to the `incomparable` materiality label.
- `EvidenceComparatorTest` asserts missing/erased/tampered evidence returns
  `summary_status: "incomparable"` with a stable reason.
- `ConveyorEvidenceTimeMachineTest` exercises the artifact comparison command
  against canonical subject descriptors rather than raw database access.

### the ambiguous fixture abstains

Evidence:

- `Conveyor.FailureDiagnosis` returns `primary_classification: "unknown"` and
  `abstained: true` when deterministic evidence is insufficient.
- `FailureDiagnosisTest` proves an ambiguous subject abstains instead of forcing
  a diagnosis.
- `Recovery.HonestyEvalTest` measures abstention rate and appropriateness so
  ambiguous traps remain visible in qualification reports.

### diagnosis remains immutable

Evidence:

- `Conveyor.FailureDiagnosis` records stable rule-bundle and diagnostic-version
  data, keeps agent hypotheses as competing hypotheses, and computes a stable
  diagnosis digest over deterministic fields.
- `FailureDiagnosisTest` proves repeated diagnosis over the same evidence yields
  the same digest and that structured control-plane signals classify before
  agent hypotheses.

### semantic recovery requires normal authority

Evidence:

- `Conveyor.Recovery` separates registry-backed `RecoveryProposal` creation from
  separately authorized `RecoveryAction` records.
- `RecoveryTest` proves a semantic recovery that requires a new spec remains
  `human_required` even when operational safety criteria are present.
- `Conveyor.Evidence.InvalidationPreview` provides the deterministic impact
  preview used before applying semantic edits.

### safe actions are idempotent, fenced, budgeted, and grant-admitted

Evidence:

- `Conveyor.Recovery.safe_auto_action_decision/2` requires deterministic
  preconditions, current fencing, an active grant, budget reservation,
  idempotency, and bounded retry evidence before returning `auto_applicable`.
- `RecoveryTest` asserts every required safe-auto criterion is present and no
  failed criteria remain before auto-apply is allowed.
- `Recovery.HonestyEvalTest` reports harmful-action rate, recovery success,
  idempotency, effect reconciliation correctness, and invalidation prediction
  accuracy.

### raw shell commands are not authoritative recovery data

Evidence:

- `Conveyor.Recovery` accepts only typed registry action keys.
- `RecoveryTest` proves an attempted `raw_shell` recovery action is rejected.
- `RecoveryAction` records retain typed action keys, authorization references,
  argument digests, and idempotency keys rather than shell command text.

## Impact Preview Evidence

- `Conveyor.Evidence.InvalidationPreview` computes
  `preview_invalidation` from ArtifactInput rows, interface bindings, decision
  blocks, verification obligations, and approval roots.
- `InvalidationPreviewTest` proves selective invalidation covers each index and
  that low impact confidence fails wide across the known indexes.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `EvidenceComparatorTest` | missing evidence, unauthorized evidence, erased evidence, digest mismatch, materiality precedence | none |
| `ConveyorEvidenceTimeMachineTest` | stale subjects, material diffs, grant/plan/artifact comparison commands | none |
| `FailureDiagnosisTest` | ambiguous diagnosis, deterministic control-plane classification, hypothesis separation | none |
| `RecoveryTest` | unknown action keys, raw shell rejection, proposal/action separation, safe-auto criteria, semantic human gate | none |
| `Recovery.HonestyEvalTest` | precision/recall errors, inappropriate abstention, harmful recovery action, reconciliation mismatch, invalidation mismatch | none |
| `InvalidationPreviewTest` | missed interface/obligation/root impact, low-confidence narrow invalidation | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the B6 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
