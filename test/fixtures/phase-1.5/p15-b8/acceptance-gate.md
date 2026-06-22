# P15-B8 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: `qualification_gate`, scoped `QualificationGrant` issuance, release
report projection, offline qualification bundle verification, and
`PhaseNextDecision` authorization/hardening.

## Exit Criteria

### requested scope is machine-readable and compared with the issued scope

Evidence:

- `Conveyor.Qualification.Gate` accepts a structured `requested_scope` and
  carries it through the gate result.
- `Conveyor.Qualification.Grants` compares `requested_scope` with the supported
  evidence scope before emitting a grant.
- `QualificationGateTest`, `QualificationGrantsTest`, and
  `ConveyorQualificationGateTest` prove covered scopes pass while uncovered
  scopes block the command.

### no failed case/sample is omitted

Evidence:

- `Conveyor.Qualification.Gate` preserves blocking findings and live sample
  policy status in the canonical gate result.
- `Conveyor.Battery.ReleaseReport` keeps canonical blockers and excluded cases
  as structured fields.
- `QualificationGateTest` proves failed hard blockers, replay misses, and live
  policy failures are surfaced as stable finding keys.

### every waiver has owner/expiry/control/autonomy effect

Evidence:

- `Conveyor.Qualification.Report` publishes active waiver records with owner,
  expiry, compensating controls, and max autonomy.
- `QualificationReportTest` proves waiver controls remain structured report
  fields and cannot be hidden by prose.

### the grant is bound to adapter/profile/archetype/environment/policy/verification

Evidence:

- `Conveyor.Qualification.Grants` emits schema-valid `QualificationGrant`,
  `QualificationScopeLattice`, `AdmissionPermit`, and `PermitCheckpoint`
  resources.
- The grant projection binds adapter, archetype, environment-restricted scope,
  policy digest, environment digest, deployment digest, max autonomy, and live
  quality bands.
- `QualificationGrantsTest` validates the emitted grant/permit/checkpoint
  resources against the P15-B8 schemas.

### a broader requested scope fails if only a narrow grant is supported

Evidence:

- `Conveyor.Qualification.Grants` returns `{:deny, %{reasons:
  [:scope_not_covered]}}` before emitting authority if the supported evidence
  scope is narrower than the request.
- `ConveyorQualificationGateTest` proves `mix conveyor.qualification_gate`
  converts that denial into a blocking gate result with
  `qualification_gate_grant_denied`.

### `qualification_gate` is reproducible from immutable evidence

Evidence:

- `Conveyor.Qualification.Bundle` builds an offline-verifiable bundle carrying
  registry digest, canonicalization profile, grant-scope digest, evidence root,
  root manifest digest, run digest, hard invariant verdicts, canary refs,
  replay anchors, waiver availability, and signature status.
- `ConveyorQualificationBundleTest` proves
  `mix conveyor.qualification_bundle_verify --offline` verifies the bundle
  without live database access.
- `QualificationBundleTest` proves a tampered grant-scope digest fails offline
  verification.

## Phase Decision Evidence

- `Conveyor.Qualification.PhaseNextDecision` records a schema-valid
  `PhaseNextDecision` with requested scope, grant id, authorization result, and
  either P2 authorization or a targeted `gate_first` hardening branch.
- `QualificationPhaseNextDecisionTest` proves covered grants authorize P2 scope
  and insufficient grants open a stop-the-line hardening branch.

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P15-B8 qualification test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
