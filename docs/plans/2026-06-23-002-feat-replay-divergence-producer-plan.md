---
title: "fix: Honest replay-fidelity status — stop certifying unearned replay"
type: fix
date: 2026-06-23
origin: docs/brainstorms/2026-06-23-replay-divergence-producer-requirements.md
---

# fix: Honest replay-fidelity status — stop certifying unearned replay

## Summary

Stop the run report from certifying replay fidelity it never checked. Replace the
hardcoded `replay_fidelity.status = "matched"` in `replay_report/2` with the honest
`baseline_absent` — the same vocabulary the gate already uses for "no replay
comparison was performed." The full cross-run producer is deferred; see Scope
Boundaries for why.

---

## Problem Frame

Replay has two surfaces and only one of them lies. The trust gate reads a
`replay_divergence` key that nothing writes, so it already defaults to
`:baseline_absent` and is renormalized to non-blocking — the gate is honest.

The lie is in the operator report: `replay_report/2`
(`lib/conveyor/planning/serial_driver.ex:229`) stamps
`replay_fidelity.status = "matched"` unconditionally, and that flows to the run
report via `lib/mix/tasks/conveyor.run.ex:72`. Every report certifies perfect
replay fidelity whether or not anything was compared.

The original plan for this work was a cross-run digest *producer* that would feed a
real verdict to both surfaces. Document review (see Sources) showed that mechanism
delivers almost no live signal: in normal operation every slice is
`:baseline_absent` forever (resume replays committed slices rather than re-running
them, and within-run rework shares the run's id), and on the passing path the
outcome digest is invariant, so it could only ever read a vacuous `:none`. The
honest, sufficient fix for the stated goal — "make the gate honest" — is to remove
the one real lie and defer the producer until it can earn its keep.

---

## Key Decisions

- **Shrink to the honest minimum.** The goal is an honest gate, and the gate is
  already honest; only the report's hardcoded `"matched"` is false. Emit the honest
  value and stop. This is a near-trivial change with no new persistence, no new
  query, and no gate wiring — versus a multi-unit producer that review showed would
  add machinery for ~no live signal.

- **`baseline_absent`, reusing the gate's vocabulary.** The report's status uses the
  same trit the gate consumes (`none` / `diverged` / `baseline_absent`). With no
  producer, the honest status is `baseline_absent` ("no baseline to compare against
  yet"), so the report and the gate now tell the same true story.

- **Keep `replay_digest`.** The digest computed in `replay_report/2` is a real
  content fingerprint of the normalized event stream, not a fabricated status.
  Retain it; only the `status` field was the lie.

---

## Requirements

- R1. The run report's `replay_fidelity.status` reflects that no replay comparison
  was performed — it emits `baseline_absent`, never an unconditional `matched`
  (origin R2, R5).
- R2. The gate path is unchanged: `replay_divergence` stays `baseline_absent` and
  non-blocking. No producer is added in this work (origin R4, R6 remain satisfied by
  the existing gate, not by new code).
- R3. The computed `replay_digest` is retained in the report.

---

## Implementation Units

### U1. Emit the honest replay-fidelity status

- **Goal:** Replace the hardcoded `"status" => "matched"` with `"baseline_absent"`
  and update any assertion that expected `"matched"`.
- **Requirements:** R1, R3
- **Dependencies:** none
- **Files:**
  - `lib/conveyor/planning/serial_driver.ex` (`replay_report/2`, ~229-245)
  - `test/conveyor/planning_serial_driver_test.exs` (or the existing driver/report
    test that asserts the replay-fidelity block; locate the current `"matched"`
    assertion and update it)
- **Approach:** Change the literal `"status" => "matched"` to
  `"status" => "baseline_absent"`. Add a short code comment noting no replay producer
  exists yet and pointing at the deferred follow-up. Keep `replay_digest`,
  `schema_version`, and `event_count`. Search the test suite for existing assertions
  on `replay_fidelity`/`"matched"` and update them to expect `baseline_absent`.
- **Patterns to follow:** the gate's status vocabulary in
  `lib/conveyor/gate/trust_evidence.ex:121-130` (`:none` / `:diverged` /
  `:baseline_absent`).
- **Test scenarios:**
  - The report's `replay_fidelity.status` is `baseline_absent` for a normal run.
  - No run path emits `"matched"` (the hardcoded literal is gone — grep-style
    assertion or an explicit "never matched without a producer" test).
  - `replay_digest` is still present and non-empty in the report.

---

## Scope Boundaries

### Deferred to Follow-Up Work

The cross-run digest producer (originally U1–U4 of this plan) is deferred. Document
review established it delivers almost no live gate signal as designed:

- A verdict other than `baseline_absent` is produced only when the *same contract
  slice* runs in a second, separate `mix conveyor.run`. Resume replays
  already-committed slices instead of re-running them, and within-run rework shares
  the run's id (excluded by the baseline's own-run filter) — so neither produces a
  comparison. In normal "run a plan once" operation, no comparison ever happens.
- Even when it does fire, the passing-path outcome digest is invariant, so it can
  only read a vacuous `:none`; the fields that vary live on the parked/rework path
  and are agent-driven and non-deterministic (noise).

The version that would fire every run is **arm (a): record agent I/O into the live
run path** so a run can be deterministically re-executed and diffed — true
fixed-input factory determinism. That is materially larger (new recording
infrastructure in the hot path) and should be reconsidered via `ce-brainstorm` if
replay is to become a live gate dimension. Until then, the gate's replay component
stays honestly `baseline_absent` and non-blocking.

Also deferred (unchanged from origin): agent-stability replay with a thresholded
"acceptable divergence" (origin Approach B); a debugging surface over a divergence
vector (origin A5).

---

## Sources / Research

- The lie: hardcoded `replay_fidelity.status = "matched"` —
  `lib/conveyor/planning/serial_driver.ex:229-245` (`replay_report/2`); surfaced to
  the operator at `lib/mix/tasks/conveyor.run.ex:72`.
- The gate is already honest: `replay_divergence` is unwritten and defaults to
  `:baseline_absent` — `lib/conveyor/gate/trust_evidence.ex:57,121-130`;
  `lib/conveyor/gate/trust_score.ex:80,109-118`.
- Why the producer was deferred (review findings): resume replays committed slices
  and rework shares `run_id`, so only a fresh separate run of the same contract slice
  yields a comparison; the passing-path outcome digest is invariant (vacuous
  `:none`). Driver execution semantics: `lib/conveyor/planning/serial_driver.ex`
  (`execute_order`, `run_slice` → `run_gate` ordering),
  `lib/conveyor/planning/run_reconstruction.ex:74`.
- Origin requirements —
  `docs/brainstorms/2026-06-23-replay-divergence-producer-requirements.md`.
