---
title: "Replay fidelity needs fixed-input re-execution, not cross-run comparison"
date: 2026-06-24
category: architecture-patterns
module: "conveyor/planning/serial_driver + conveyor/gate"
problem_type: architecture_pattern
component: tooling
severity: medium
applies_when:
  - "adding replay, reproducibility, or cross-run comparison signal to the serial driver or trust gate"
  - "tempted to compare a run's outcome digest against a prior run's digest"
  - "emitting an operator-report verdict (matched/verified/passed) for a check that did not run"
related_components:
  - testing_framework
  - documentation
tags:
  - replay
  - gate
  - trust
  - serial-driver
  - reproducibility
  - determinism
  - cassette
  - baseline-absent
---

# Replay fidelity needs fixed-input re-execution, not cross-run comparison

## Context

A "gate honesty" sweep over the serial driver found a report field that certified a
signal it never measured. `replay_report/2` in `lib/conveyor/planning/serial_driver.ex`
assembled a `replay_fidelity` block whose `status` was the literal string `"matched"` —
hardcoded, with no comparison behind it. Every run, the operator-facing run report
(`lib/mix/tasks/conveyor.run.ex:72`) told the operator replay had been verified and
matched a baseline. No baseline existed; nothing was ever compared.

The obvious remediation was to "make it true": build the missing cross-run producer —
digest this run's outcome, compare against a prior run's stored digest, emit a real
`matched` / `diverged` verdict. A multi-agent review of that plan produced the durable
lesson: the cross-run producer, even fully built, would emit a real signal in essentially
no normal run, and on the one path where it could fire the signal would be vacuous or
pure noise. The "obvious fix" was a multi-unit machine wired to a dead input. What the
situation called for was a one-word honesty fix plus a written reason not to build the
big thing.

## Guidance

**(a) The operator report must never certify a signal it did not compute.** When no
replay comparison runs, say so. Emit `baseline_absent` — the gate's own vocabulary for
"there is no baseline to compare against" — not an unearned `matched`. The change in
`replay_report/2`:

```elixir
# Before — certifies a comparison that never ran:
"replay_fidelity" => %{
  "schema_version" => "conveyor.replay_fidelity@1",
  "status" => "matched",
  "digest" => digest,
  "event_count" => length(events)
}

# After — honest absence; digest/schema/count retained:
"replay_fidelity" => %{
  "schema_version" => "conveyor.replay_fidelity@1",
  "status" => "baseline_absent",
  "digest" => digest,
  "event_count" => length(events)
}
```

The `digest`, `schema_version`, and `event_count` are honest facts the run did compute;
only the unearned verdict was wrong.

**(b) Replay/reproducibility as a LIVE gate dimension requires FIXED-INPUT re-execution,
not cross-run output comparison.** A genuine reproducibility check re-runs the same work
against the *same recorded inputs* and asserts the outputs match — what cassette replay
through the deterministic `ReplayEngine` (`lib/conveyor/cassettes/replay_engine.ex`) does,
with strict per-event equality (ADR-12: exact equality, no fuzzy thresholds). Comparing
one run's *outcome* digest against a *different* run's outcome digest is not
reproducibility; it compares two different experiments and calls a difference a
divergence.

**(c) Do not plan a cross-run digest producer expecting a live signal.** It will not fire
in normal operation, and where it can fire it is vacuous or noisy (worked through below).
The deferred plan is parked at
`docs/plans/2026-06-23-002-feat-replay-divergence-producer-plan.md`, and the in-code
comment points there so the next person inherits the reasoning, not just the gap.

## Why This Matters

A replay/reproducibility gate dimension wired to cross-run comparison fails in two
directions at once. In normal one-pass operation it sees no second run, so it **never
fires** (always abstains); and on the rework path, where a second execution exists, the
only fields that vary are agent-driven and non-deterministic, so it **fires on noise**.
Either way the operator gets a number that means nothing — and the original bug made it
worse by reporting a confident `matched` on top of that nothing. A report that lies is
more dangerous than one that abstains: an operator who trusts `matched` skips the scrutiny
the gate exists to trigger.

The reason the bug was *only* a reporting lie — not a broken gate — is a deliberate
**two-surface split**:

- **The gate reads `replay_divergence`**, never `replay_fidelity`
  (`lib/conveyor/gate/trust_evidence.ex:57`). Nothing in the live path writes that key, so
  it defaults to `:baseline_absent`; the OD19 weight renormalization in
  `lib/conveyor/gate/trust_score.ex` drops replay's weight to zero on `:baseline_absent`
  and `replay_ok?` treats it as non-blocking. The gate was already honest — it correctly
  treated replay as "no baseline yet, contributes nothing."
- **The report carries `replay_fidelity`**, a separate operator-facing field
  (`conveyor.run.ex:72`) with zero influence on any gate decision. This was the only
  surface lying.

Because the two surfaces are independent, the fix was localized to the report and could
not regress the gate. Had they shared one field, the same hardcoded `matched` would have
silently turned a non-blocking abstain into a blocking false-pass — a far worse failure.
The split is why a certify-what-you-didn't-compute bug stayed cosmetic.

## When to Apply

- Adding any replay, reproducibility, or cross-run comparison signal to the serial driver
  or the trust gate.
- Tempted to compare a run's outcome digest against a prior run's digest and treat any
  difference as a divergence verdict.
- Emitting any operator-report field that names a verdict (`matched`, `verified`,
  `passed`, `clean`): if the run did not perform the check, emit the honest
  "absent/not-computed" value, not the success value.
- The deeper trigger: any time a "make the lie true" fix would require building a producer,
  first confirm the producer would actually produce a meaningful signal under normal
  operation. If it fires never, or only on non-deterministic fields, the honest-absence
  value plus a recorded rationale is the correct ship — not the machine.

## Examples

**1. The fix.** `"matched"` → `"baseline_absent"` in `replay_report/2`, digest/schema/count
preserved, two test assertions updated (`first_light_serial_driver_test.exs`,
`conveyor_operator_tasks_test.exs`). One-line honesty fix; no new producer. Shipped as
PR #22 / commit `22a9268`.

**2. Why cross-run comparison is vacuous — the walkthrough.** Trace every path on which a
verdict other than `:baseline_absent` could appear:

- **Resume.** `resume!/3` → `execute_order` replays already-committed slices from the
  ledger rather than re-running them; a gate-passed slice is the durable boundary and is
  never re-executed. So resume never produces a second outcome to compare.
- **Within-run rework.** `run_one_with_rework!/5` does re-execute a slice, but every
  attempt shares the *same* `run_id` (minted once per run). A baseline keyed to
  `(project_id, slice_id)` excludes the current run via its own-run filter, so rework
  attempts never form a comparable pair either.
- **What's left.** A non-`:baseline_absent` verdict can therefore only arise from a
  *fresh, separate* `mix conveyor.run` of the same contract slice — never in normal
  one-pass operation, where every slice stays `:baseline_absent` forever. And even there,
  the normalized **outcome** digest (`normalize_replay_event/1` keeps `status`,
  `gate_result`, `run_attempt_outcome`, `findings`) is **invariant on the passing path**
  (`status=passed`, `gate_result=pass`, `findings=[]`) → a vacuous `:none`. The fields
  that vary (rework counts, parked findings) live on the rework/parked path and are
  agent-driven and non-deterministic — noise. The producer's output is dead on the green
  path and untrustworthy on the red path.

**3. What "arm a" (live cassette recording) would change.** The only way to make replay a
signal that fires *every* run is a fixed-input check: record the agent's tool-I/O into the
live execution path (a cassette), then re-execute deterministically through `ReplayEngine`,
which already enforces strict equality (a `:missed` hard-blocks per ADR-23). That is true
factory-determinism — same inputs in, byte-identical outputs out — and fires on every run.
But the live path records **no** cassette today; recording exists only in the eval/test
path (`lib/conveyor/eval/lift_duel.ex` via the cassette bridge). Adding live recording is
materially larger net-new infrastructure, which is why it was deferred rather than smuggled
in under a one-line bug fix.

## Related

- ADR-12 — cassette causal replay and mode-specific freshness (exact replay equality):
  `docs/adrs/adr-12-cassetteseries-causal-replay-and-mode-specific-freshness.md`
- ADR-23 — ternary gate verdict / calibrated abstention (why `baseline_absent` is the
  honest non-blocking value): `docs/adrs/adr-23-ternary-gate-verdict-calibrated-abstention.md`
- ADR-04 — canonicalization / digest semantics (the passing-path digest invariance):
  `docs/adrs/adr-04-canonical-schema-registry-digestref-and-canonicalization.md`
- Origin brainstorm: `docs/brainstorms/2026-06-23-replay-divergence-producer-requirements.md`
- Deferred producer plan (carries the deferral rationale):
  `docs/plans/2026-06-23-002-feat-replay-divergence-producer-plan.md`
- Event-sourced ledger plan (the resume/rework machinery this reasons about):
  `docs/plans/2026-06-23-001-feat-event-sourced-run-ledger-plan.md`
- PR #22 — the triggering fix.
