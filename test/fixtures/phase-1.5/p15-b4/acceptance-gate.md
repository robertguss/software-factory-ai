# P15-B4 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: VerificationObligations, Test Integrity, waivers, quarantine, compiler
falsifier preservation, and operator Cockpit projection.

## Exit Criteria

### readiness is per obligation, not TestPack aggregate

Evidence:

- `Conveyor.Verification.new_evidence_requirement!/1` records typed required
  dimensions per obligation.
- `Conveyor.Verification.evaluate_requirement/3` emits
  `conveyor.obligation_satisfaction@1` results per
  `verification_obligation_id`.
- `EvidenceRequirementTest` proves a wrong evidence dimension cannot satisfy a
  required dimension through a generic stage ordering.

### required flake/non-hermetic/vacuity blocks

Evidence:

- `Conveyor.Verification.IntegritySentinel.run/3` emits
  `trustworthy`, `suspect`, `untrustworthy`, or `not_assessed` verdicts from
  calibration, hermeticity, repeatability, mount, artifact, hidden dependency,
  and falsifier preservation probes.
- `TestIntegritySentinelTest` proves non-hermetic controls and production-source
  mutation are `untrustworthy`, unstable repeatability is `suspect`, and missing
  required observations remain `not_assessed`.
- `EvidenceRequirementTest` proves suspect/invalid/expired evidence blocks
  obligation satisfaction.

### quarantine cannot satisfy an obligation

Evidence:

- `Conveyor.Verification.new_quarantine!/1` records `TestQuarantine` lifecycle
  state with reasons `flaky`, `non_hermetic`, `vacuous`, `order_dependent`, and
  `infrastructure_sensitive`.
- `EvidenceRequirementTest` proves quarantined evidence is blocked rather than
  satisfying an obligation, while replacement valid evidence can satisfy it.

### active waiver requires human decision, owner, expiry, controls, max autonomy

Evidence:

- `Conveyor.Verification.new_waiver!/1` validates active waivers require
  `human_decision_id`, `owner`, `expires_at`, `compensating_control_refs`, and
  `max_autonomy`.
- `VerificationResourcesTest` covers valid active waivers and rejects missing
  human decision or compensating controls.
- `EvidenceRequirementTest` proves waiver satisfaction remains explicit
  `waived`, not valid evidence.

### human-observed evidence is distinct from machine evidence

Evidence:

- `Conveyor.Verification.new_evidence!/1` constrains
  `human_observation` as a separate `VerificationEvidence.evidence_kind`.
- `VerificationResourcesTest` records human-observed evidence with a
  `human_observer` producer and does not fold it into candidate or machine
  evidence.

### repeated TestIntegrityRun samples are permitted and comparable

Evidence:

- `Conveyor.Verification.IntegritySentinel.run/3` records `sample_no`,
  `integrity_spec_digest`, `probe_results`, `verdict`, and
  `integrity_run_digest`.
- `TestIntegritySentinelTest` covers deterministic sample output and
  repeatability comparison from multiple observed result digests.
- `EvidenceKernelResourcesTest` validates `conveyor.test_integrity_run@1` and
  related B4 schemas through registry examples.

## Additional Evidence

- `FalsifierSeamTest` proves compiler-derived falsifier seeds must be preserved,
  translated, or explicitly superseded; dropped seeds produce a blocking report.
- `VerificationCockpitTest` proves the Cockpit projection exposes obligation
  coverage, invalid evidence, waivers, owners, expiry, and quarantines without
  rewriting authority.
- `EvidenceKernelResourcesTest` validates the JSON schemas and examples for:
  `VerificationObligation`, `VerificationEvidence`, `ObligationSatisfaction`,
  `VerificationWaiver`, `TestIntegrityRun`, and `TestQuarantine`.

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the B4 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
