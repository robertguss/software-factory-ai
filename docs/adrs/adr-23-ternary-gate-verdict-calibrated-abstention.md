# ADR-23: Ternary gate verdict and calibrated abstention

Status: Accepted

Date: 2026-06-20

Bead: (to be assigned)

Amends: ADR-02 (extends `not_assessed` precedent to the deterministic gate),
ADR-13 (abstain is a distinct outcome from quarantine).

## Context

The deterministic gate is currently binary: a run either passes all required
stages or it fails. This binary framing assumes that "all required stages
passed" is sufficient evidence to merge unattended. It is not. The field's
central unsolved problem for autonomous operation is the reliability gap:
accuracy is improving faster than reliability, so an agent that succeeds on most
tasks but fails unpredictably on the rest is unacceptable as an autonomous
system. A binary gate cannot express "the stages passed, but I am not confident
this verdict is trustworthy."

Conveyor already computes the signal needed to detect untrustworthy passes and
discards it. `Conveyor.Verification.IntegritySentinel`
(`lib/conveyor/verification/integrity_sentinel.ex`) runs ten anti-vacuity probes
(base calibration, falsifier survival, hermeticity, repeatability, mapping,
mount boundary, required artifacts, source mutation, hidden dependency, falsifier
preservation) and produces a verdict that records trustworthiness but drives no
control-flow decision. Acceptance calibration, baseline health, and replay
divergence diagnostics are likewise observational. ADR-02 already established the
principle that a gate must report `not_assessed` rather than pass by default when
evidence is insufficient; that principle currently lives only in the live
statistical layer, not in the deterministic gate.

## Decision

The gate verdict is ternary: `pass`, `fail`, or `abstain`.

An `abstain` verdict means every required stage passed but the conductor is not
calibrated-confident the pass is trustworthy. Abstain is a fail-closed outcome:
it never auto-merges and never satisfies an obligation. It routes the slice to
human adjudication (the parked queue), carrying the evidence that triggered it.

A calibrated `TrustScore` is computed per attempt by fusing already-recorded
signals: the `IntegritySentinel` probe results, acceptance calibration state,
baseline health, replay divergence, and the historical pass rate for this slice
archetype from the corpus. The score is a calibrated estimate of P(this verdict
is correct), not an agent self-report. Two thresholds, declared in policy and
content-addressed, partition the score into auto-accept, abstain, and (where the
stages failed) fail.

Thresholds are conservative by default: with a thin corpus the system abstains
liberally and loosens only as calibration evidence accumulates. Threshold
changes create a new policy digest and cannot reinterpret prior verdicts
(consistent with ADR-02 and ADR-04).

The determinism boundary holds. The `TrustScore` and the threshold partition are
computed by the conductor from recorded evidence; no agent input enters the
score. Abstain is a conductor decision, not an agent judgment.

## Consequences

The `Gate.Finalizer` gains an `:abstain` action and slice-state target distinct
from `:request_rework`. Today `finalize!/3` maps a non-fatal gate failure to
`:request_rework` and the slice to `:needs_rework`; abstain is a separate edge
that targets the human-adjudication queue with status preserved as a passed-but-
unconfident attempt, not a rework.

Verdict, evidence, and report schemas must carry the third outcome and the
`TrustScore` with its component breakdown and the policy digest used. Reports
must never collapse abstain into pass or into fail.

The parked queue becomes a calibrated triage list rather than a dumping ground:
its size is a direct, measurable function of the system's self-honesty, and it is
the natural surface for the operator attention model (the ambient-teammate UX).

Operator overrides of an abstain (merging anyway, or rejecting a high-confidence
pass) are recorded as labeled calibration examples that tune the score over time.
This is the intended learning loop and must be captured in the ledger.

## Implementation Notes

`TrustScore` is a pure function over recorded evidence; like the qualification
gate evaluator it should have no I/O so it can run offline and be re-evaluated
against historical runs. Calibration method is not hardcoded; record the method
or policy digest with each score (mirroring ADR-02's stance on statistical
methods).

The abstain threshold must default such that the known-good reference solution
used for `loop_integrity` always lands in auto-accept; if a known-good reference
abstains, the calibration is miscalibrated and that is a release-blocking
condition, not a normal abstain.

Abstain must not be reachable when a required stage failed; fail dominates
abstain, and abstain dominates pass.

## References

- docs/RADICAL-LEVERAGE-IDEAS.md, idea 1 (the Reliability Engine) and heresy H1.
- ADR-02 (`not_assessed` over pass-by-default; statistical method recording).
- ADR-13 (VerificationObligations: quarantine is not satisfaction).
- `lib/conveyor/verification/integrity_sentinel.ex`, `lib/conveyor/gate/finalizer.ex`.
