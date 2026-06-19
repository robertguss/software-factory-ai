# P2-B8 Quality Hypothesis Comparison

Status: compared against available P2-B pilot evidence.

Misses remain misses until a recorded PhaseNextDecision changes a hypothesis.
No PhaseNextDecision has changed these hypotheses yet.

## Observed Pilot Evidence

Source: the pre-registered P2-B7 pilot and B8.1 release-suite evidence.

Observed metrics:

- approved-without-rewrite rate: `1.0`
- median repair rounds: `1`
- first-pass deterministic gate success: `0.3333333333333333`
- material dispute rate: `0.3333333333333333`
- Critic planted loophole catch rate: `1.0`
- lost falsifier or obligation count: `0`
- impact preview match rate: `1.0`

## Comparison

| Hypothesis | Target | Observed | Status |
| --- | --- | --- | --- |
| approved_without_rewrite | >= 80% | 100% | met |
| median_repair_rounds | <= 1 | 1 | met |
| first_pass_gate_success | >= 70% | 33.33% | missed |
| material_dispute_rate | < 20% | 33.33% | missed |
| critic_planted_loophole_catch | 100% | 100% | met |
| lost_falsifier_or_obligation | 0 | 0 | met |
| impact_preview_matches_actual | 100% | 100% | met |

Summary: 5 met, 2 missed, 0 superseded_by_phase_next_decision.

## Interpretation

The pilot supports release-suite correctness evidence, but it does not support
automatic Phase 3 advancement. The missed `first_pass_gate_success` and
`material_dispute_rate` hypotheses remain release-gate misses until a later
PhaseNextDecision explicitly changes the hypotheses or chooses a hardening path
that accepts the reduced autonomy implications.
