# M4 — Activate the trust gate: progress & blockers

> Branch `m4-gate-honesty` / PR #19. Status as of the overnight 2026-06-23
> session. This is the deterministic "A-first" slice of M4 (no live-agent runs).
> It is **partial by design**: the keystone de-laundering landed, but the
> producer fail-closed _flips_ (baseline, calibration) are **blocked on
> corpus-readiness work** the recovered M4 plan itself says must be done first
> ("STOP AND FIX THE CORPUS"). See §3.

## 1. What landed (green: deterministic 888 + eval 71)

### A1 — de-launder the evidence layer (the keystone) — `6c8a273`

`Conveyor.Gate.TrustEvidence.from_run_output/1` was laundering every
_unmeasured_ signal to its passing token, which made the calibrated `:abstain`
band **structurally unreachable** on the live path. Now an always-assessable
signal that is expected-but- absent fails closed:

| signal          | absent before A1       | absent after A1                                              |
| --------------- | ---------------------- | ------------------------------------------------------------ |
| calibration     | `:valid` (auto-accept) | `:not_assessed` → **abstain/park**                           |
| baseline        | `:green` (auto-accept) | `:unknown` → **abstain/park**                                |
| integrity       | `"trustworthy"`        | `"trustworthy"` (still laundered — owned by D4/M4.8, see §4) |
| replay / corpus | `:none` / `nil`        | unchanged (owned by stream B)                                |

Added: a `:declared_not_assessable` mechanism (`"trust_not_assessable"` output
key) for genuinely backend-N/A signals; explicit `"passed"`→`:green` mapping.

- **A7** `test/support/trust_discrimination.ex` — reusable
  `assert_discriminates/1` + `band_of_output/1` (drives the real assembly path).
- **A6** `test/conveyor/gate/reference_auto_accept_test.exs` — the re-tune brake
  as an executable anchor: pins the reference at **0.925** and guards the
  forbidden **0.775** transient (un-laundering integrity without a real probe
  parks the reference).
- End-to-end guard added to `gate_finalizer_test.exs`: a run output missing the
  calibration signal abstains and parks through the real `Finalizer.finalize!`
  path.

### A7d — empty acceptance suite fails the gate (dr1m.7) — `52a0401`

An acceptance suite that ran **zero tests** used to vacuously PASS. Closed at
three independent layers (toolchain producer, DB rerunner, gate-stage backstop),
each keyed on real per-test enumeration so status-only/stdout suites are
unaffected. **Closes dr1m.7.**

## 2. Verified gate behaviour (before → after)

- Before: `TrustScore` always `:auto_accept`; abstain unreachable on the live
  path.
- After: a passed gate with an absent/`:invalid` calibration or absent/`:red`
  baseline **abstains → slice `:parked`**; a fully-green reference still
  auto-accepts at 0.925.
- The committed reference (`samples/beads_insight`) still auto-accepts through
  the live m1/m2/m3 production-loop pipeline (real pytest). No weight/threshold
  change.

## 3. The two Open Decisions — RESOLVED

### Decision 1 (baseline A2/A3): **do NOT force it fail-closed** — resolved, no machinery

Baseline regression is **already enforced by the `test_execution` gate STAGE** —
a red baseline _fails_ the gate (it never reaches trust evaluation, since
`TrustScore` only adjudicates _passed_ gates). So the baseline _trust signal_ is
**redundant**, and forcing it fail-closed (the original A2/A3 plan) would **park
the greenfield reference** (slice-1 has no green regression surface — the corpus
is RED on the clean seed by design) for **zero added safety**. Resolution: keep
A1's behavior (a real `:failed` still abstains; absence stays non-blocking). The
heavy A2/A3 work (materialize DB suites + the OD19-style weight renormalization)
is **unnecessary** and is dropped. _No code change; no reference risk._

### Decision 2 (calibration A4/A5): **LANDED** — real calibration; not-valid parks for investigation

`AcceptanceCalibration` _fabricated_ `:valid` (its runner never executed). Now
made real and honest, in two coupled parts (commit `0c21a26`):

- **A4 — real calibration in an isolated base checkout.** The station runs the
  locked acceptance commands against the base in a **detached `git worktree` at
  `base_commit`** (`stations/acceptance_calibration.ex`), never the live
  workspace. (A first attempt ran pytest in the _live_ tree and broke the
  reference — the cumulative cache/artifact pollution made
  `reference_slice_007`'s patch fail to apply; the worktree isolates the run.)
  Calibration is `:valid` only when the tests genuinely fail on base.
- **A5 — disposition: `:valid` proceeds, anything else parks.** Calibration is a
  **trust signal, not a gate-stage pass/fail** (`gate/stages/test_execution.ex`
  no longer fails on it). An acceptance suite that passes on base (`:invalid`)
  or that couldn't be calibrated (`:not_assessed`/missing) is **not broken
  code** — reworking the code can't fix a weak _locked_ test — so it routes to
  the trust score, which **abstains → parks** the slice for human + AI
  investigation, instead of hard-failing → reworking (which crashed on patch
  re-apply).

**Net (the gate now catches a real weak slice):** beads_insight **SLICE-007**'s
acceptance tests pass on base (they don't pin down its `report.py` change), so
it now correctly **parks** instead of auto-accepting. The reference's honest
end-to-end story is now **6 accepted + 1 parked** (`first_light` updated to
prove it); m1/m2/m3 (slices 1–6) unchanged. Deterministic **909** + eval **71**
green.

`tasks_service` (green-on-base) is **not on the reference trust path**, so it's
unaffected; if it ever is, `:invalid` is the correct signal for it too (its
acceptance tests don't prove new behavior). Optional future polish: split
`:invalid` into typed park _reasons_ (`weak_acceptance_tests` vs
`no_behavior_change`) for the investigators — additive, not needed.

### Integrity un-laundering (the strongest signal) — **LANDED** (commit `5b1c047`)

A1 left integrity laundered (`TrustEvidence.integrity` always emitted
`"trustworthy"`). Integrity is the highest-weighted signal (0.30), so this was
the largest remaining honesty gap. Now real, without needing the docker hermetic
gate first: on `:local` the verify station requires only the **backend-agnostic
`source_mutation` probe** (`integrity_probes/1`) — hermeticity is docker-only,
declared not-assessable on `:local` — so a clean run is genuinely
`"trustworthy"` and a real production-source mutation is `"untrustworthy"` →
abstain → park. `TrustEvidence` passes the real verdict through (absent →
`"not_assessed"`, fail-closed). The reference stays green (its integrity is now
_earned_ `"trustworthy"`, scoring 0.925 as before). This is the `:local` variant
of the spec's D4 (the docker hermetic-gate path remains a later option for
asserting hermeticity).

### Stream B core — **LANDED** (replay un-laundered + OD19 renormalization, commit `873461b`)

Replay-divergence was the last laundered signal (absent → `:none`/"matched").
Now absent → `:baseline_absent` (honest "no committed baseline yet"). **OD19**:
`:baseline_absent` is non-blocking — `TrustScore.effective_weights` drops
replay's weight and renormalizes the rest over 0.85, so the cold-start reference
auto-accepts at `0.775/0.85 = 0.9118` (the `policy_digest` hashes the _static_
weights — the renormalization is a runtime rebalance). A real `:diverged` still
parks. This completes **"all four core trust signals are honest"** (calibration,
integrity, baseline-via-stage, replay). Follow-ups (both greenfield):

- the real **replay-baseline producer** (emit `:none`/`:diverged` by comparing
  against committed-seed baselines) — gives replay actual _divergence
  discrimination_;
- the **`corpus_pass_rate` producer** (boost-only signal from cassette pass-rate
  history).

### Stream F — partial: MutantGauntlet now covers a static stage (commit `8ba0ff7`)

The gauntlet (the CI harness that proves the gate catches mutants with **zero
false-pass**) ran the corpus only through `test_execution` (behavioral mutants
via real pytest); the 5 static-stage mutants were all deferred. Now it also
discriminates the **path-based policy static stage**: `forbidden_policy_edit`
(raises `autonomy_ceiling` L1→L4 in the plan) is caught by `policy_compliance`
from its changed files alone, so `false_pass_rate` (the blocking CI metric)
covers behavioral + policy-static (4 mutants, 0 false-pass). The other 3 static
stages stay deferred (honest): `contract_lock` (matching contract digests),
`code_quality_delta` (an analyzer), `run_check`/injection-content (run
artifacts).

### Stream E — partial: policy_compliance + acceptance_mapping wired live as required stages (`2e95458`, `529f48b`)

The production gate ran 4 stages (contract_lock, diff_scope, secret_safety,
test_execution). Now **6**: two static stages are wired **required** because
both pass for the reference _and_ enforce in production —

- **policy_compliance** (`2e95458`): the reference touches no policy-controlled
  paths, so it passes; a forbidden policy edit blocks **in production**, not
  just in the gauntlet.
- **acceptance_mapping** (`529f48b`): reads `agent_brief` +
  `verification_result`, **both already in `default_gate_context`** (no new
  producer), so it needed only to be added to the list. Every reference slice's
  acceptance criteria's `required_test_refs` are exactly the tests the verify
  station runs (first_light asserts this) and are green, so it passes; a slice
  whose criterion lacks **passing evidence for a required test** now blocks.
  SLICE-007 still parks at the _trust_ layer (its tests pass, so
  acceptance_mapping passes too).

The gate respects a per-stage `required?` flag
(`stage_passes_gate?(%{required?: false}) → true`), so future stages _could_
wire advisory — but the wiring map found **no clean-advisory candidates**: of
the 7 still-unwired static stages, every one _fails_ the reference under the
production context because its input is absent and no producer threads it (so
advisory wiring would only spam blocking-missing-input findings);
`code_quality_delta` is the lone exception but emits a perpetual
`missing_code_quality_run` _warning_ with no real signal. So each remaining
stage needs a **producer** before it can be required (the honest path). Cheapest
next: **`head_tree_sha256` → workspace_integrity** — its patch_set-derived
checks are already clean for the reference and the producer already exists in
`PatchSetApplicator`; it just isn't threaded into the gate context. (Then:
observed_risk ← review_policy resolver; build_install ← build_install_result;
provenance_attestation ← prompt_sha256 + evidence_sha256; reviewer_aggregation ←
Reviews + reviewer_health; canary_freshness ← GateHealth seeder + project_id;
code_quality_delta ← CodeQualityRun + adapter contract.) Tracked: `br jmnt`.

## 4. Still out of scope this branch (later streams)

- The _rest_ of **E** (7 more static stages, each needing a producer — see §3) +
  the remaining **F** static stages + **C/D** (more integrity probes, docker
  hermetic gate) + the two **B** producers — later milestones.

## 5. Safe next steps (no corpus surgery, no live agent)

- Resolve the §3 Decisions, then land A2/A3 and A4/A5 with the base-checkout
  seam.
- Test/quality hardening: first `PlanRunner.run!/2` tests; re-enable Dialyzer;
  reconcile the ROADMAP/HANDOFF/tracker milestone narratives.
