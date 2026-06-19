# P2-B8 Acceptance Gate

Status: release-evaluation deliverable accepted; `phase2_gate failed` is visible
and opens gate-first hardening. No Phase-3 entry contract is issued.

Scope: release-suite evidence, quality-hypothesis comparison, release record,
`phase2_gate`, PhaseNextDecision, and targeted Phase 3 hardening plan.

## Exit Criteria

### every hard correctness invariant passes

Evidence:

- `release-suite-report.md` records the DB-free focused release suite:
  43 passed when combined with the report test.
- `release-suite-report.md` covers contract, security, property, replay,
  recovery, retention, and legibility suites.
- `release-suite-report.md` records `br dep cycles --json` returning no active
  cycles.
- `db_backed_mix_test_unavailable` remains visible because full DB-backed
  `MIX_ENV=test mix test` is blocked by local PostgreSQL authentication; this
  blocks production authority and is not hidden as a pass.

### the requested grant remains current for pilot/release scope

Evidence:

- `release-record.md` records the active
  `qualification_grant:sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
  for offline/local-dev pilot/release scope.
- `phase2-gate.json` compares the requested Phase 3 production scope with the
  current local-dev grant scope and fails closed.

### all waivers are explicit/scoped/expiring/reflected in autonomy

Evidence:

- `release-record.md` records WaiverBudget status as zero active waivers
  consumed by the P2-B8 release scope.
- `release-record.md` states any future waiver must carry owner, scope, expiry,
  compensating controls, and autonomy effect.

### pre-registered pilot evidence is attached

Evidence:

- `docs/phase-2/p2-b7/acceptance-gate.md` is referenced by
  `phase2-gate.json` and `phase-next-decision.json`.
- `quality-hypothesis-comparison.md` uses the P2-B7 pilot observations and
  keeps `first_pass_gate_success` and `material_dispute_rate` as misses.

### the §17.8 six/eight-dimension Phase-3 matrix is used

Evidence:

- `phase3-hardening-plan.md` uses the eight readiness dimensions from §17.8:
  Evidence/gate integrity, Grant scope/stability, Contract stability, Adapter
  reliability, Operator clarity, Serial execution, Economics/latency, and
  Operational controls.
- `phase3-hardening-plan.md` records `harden_gate_first` and lists the
  non-selected adapter, contract pipeline, operator surface, and evidence
  kernel hardening branches.

### roadmap pressure cannot hide a failed gate without visible human risk acceptance and no automatic authority

Evidence:

- `phase2-gate.json` records `status: "failed"`,
  `authorization_result: "hardening_required"`,
  `automatic_authority: false`, and `roadmap_pressure_hidden: false`.
- `phase-next-decision.json` is schema-valid, selects `gate_first`, and records
  `blocks_requested_grant: true`.
- `phase3-hardening-plan.md` says: No Phase-3 entry contract is issued.

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B8 test files.
- `jq empty` for `phase2-gate.json` and `phase-next-decision.json`.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration and is carried as explicit hardening
work, not as release authority.
