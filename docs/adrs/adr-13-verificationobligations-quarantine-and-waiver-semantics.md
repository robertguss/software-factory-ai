# ADR-13: VerificationObligations, quarantine, and waiver semantics

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.13`

Gated milestone: P15-B4

## Context

Phase 1.5 cannot treat a TestPack's aggregate color as verification authority.
Different obligations require different evidence dimensions, and a test suite
can be partly useful while still failing to satisfy a required acceptance,
policy, interface, property, or human-judgment obligation.

The plan makes the key invariant explicit: no flaky required-evidence
laundering. Quarantine never satisfies the underlying VerificationObligation.

The trust system also needs waivers, but a waiver must be a scoped, expiring,
human-owned reduction in autonomy, not a hidden pass.

## Decision

Conveyor will make `VerificationObligation` the unit of verification authority.
Readiness is evaluated per obligation, not per TestPack aggregate.

Each obligation has an `EvidenceRequirement` predicate that can require multiple
dimensions, such as specification coverage, calibration, harness validation,
candidate result, hermeticity, repeatability, adversarial challenge, mutation
assessment, human observation, or environment attestation. Evidence is recorded
as `VerificationEvidence` with producer, validity, environment fingerprint,
result digest, and evidence digest.

`ObligationSatisfaction` is the only authority-bearing satisfaction record. It
names the evidence requirement digest, consumed evidence ids, dimension-specific
results, policy decision, result, satisfaction digest, and evaluation time.
Results are limited to `satisfied`, `blocked`, `waived`, or `not_assessed`.

Quarantine is a test lifecycle state, not obligation satisfaction. A
`TestQuarantine` can mark a test as flaky, non-hermetic, vacuous,
order-dependent, or infrastructure-sensitive, and can exclude it from advisory
or ordinary execution paths. If the quarantined test was required for an
obligation, that obligation remains unsatisfied unless other valid evidence
meets the full requirement.

Waivers are explicit authority objects. An active `VerificationWaiver` requires:

- a human decision;
- an owner;
- a reason;
- expiry;
- compensating controls;
- a maximum autonomy level;
- active status.

A waiver does not delete the obligation and does not make the evidence valid. It
records a policy-approved decision to proceed under reduced autonomy and
compensating controls until expiry, revocation, or supersession.

Human-observed evidence is distinct from machine evidence. A policy can require
human observation for some obligations, but that observation must be represented
as evidence with its own producer and validity rather than folded into a test
aggregate.

## Consequences

- TestPack status is advisory until mapped through obligation-specific evidence
  requirements.
- Required flaky, non-hermetic, or vacuous evidence blocks authority rather than
  becoming green through quarantine.
- Waivers become visible operational debt with owner, expiry, controls, and
  autonomy impact.
- Cockpit and reports must show obligations, evidence, waiver state, and
  quarantine separately.
- Qualification fails if readiness can be inferred from an aggregate TestPack
  color alone.

## Implementation Notes

- Store `VerificationObligation`, `VerificationEvidence`,
  `ObligationSatisfaction`, `VerificationWaiver`, `TestIntegrityRun`, and
  `TestQuarantine` as separate resources.
- Evaluate EvidenceRequirement predicates by dimension and persist
  `dimension_results`.
- Treat suspect, invalid, expired, quarantined, or missing required evidence as
  blocking unless a valid waiver covers the obligation.
- Include integrity probes for calibration, hermeticity, repeatability, mount
  integrity, vacuity, required artifacts, and obligation coverage.
- Add Cockpit projections that expose safe next actions without rewriting the
  underlying obligation state.

## References

- Bead `software-factory-ai-aamg.1.13`.
- Phase 1.5/2 plan, section 3, law 21.
- Phase 1.5/2 plan, section 4.6, `VerificationObligation`,
  `VerificationEvidence`, `ObligationSatisfaction`, `VerificationWaiver`,
  `TestIntegrityRun`, and `TestQuarantine`.
- Phase 1.5/2 plan, section 18.2, milestone P15-B4.
- Phase 1.5/2 plan, section 27, strategy bullet on verification per obligation.
- Phase 1.5/2 plan, section 28.2, required ADR item 13.
