# M4 — Activate the trust gate: progress & blockers

> Branch `m4-gate-honesty` / PR #19. Status as of the overnight 2026-06-23 session.
> This is the deterministic "A-first" slice of M4 (no live-agent runs). It is **partial
> by design**: the keystone de-laundering landed, but the producer fail-closed *flips*
> (baseline, calibration) are **blocked on corpus-readiness work** the recovered M4 plan
> itself says must be done first ("STOP AND FIX THE CORPUS"). See §3.

## 1. What landed (green: deterministic 888 + eval 71)

### A1 — de-launder the evidence layer (the keystone) — `6c8a273`
`Conveyor.Gate.TrustEvidence.from_run_output/1` was laundering every *unmeasured*
signal to its passing token, which made the calibrated `:abstain` band **structurally
unreachable** on the live path. Now an always-assessable signal that is expected-but-
absent fails closed:

| signal | absent before A1 | absent after A1 |
|---|---|---|
| calibration | `:valid` (auto-accept) | `:not_assessed` → **abstain/park** |
| baseline | `:green` (auto-accept) | `:unknown` → **abstain/park** |
| integrity | `"trustworthy"` | `"trustworthy"` (still laundered — owned by D4/M4.8, see §4) |
| replay / corpus | `:none` / `nil` | unchanged (owned by stream B) |

Added: a `:declared_not_assessable` mechanism (`"trust_not_assessable"` output key) for
genuinely backend-N/A signals; explicit `"passed"`→`:green` mapping.

- **A7** `test/support/trust_discrimination.ex` — reusable `assert_discriminates/1` +
  `band_of_output/1` (drives the real assembly path).
- **A6** `test/conveyor/gate/reference_auto_accept_test.exs` — the re-tune brake as an
  executable anchor: pins the reference at **0.925** and guards the forbidden **0.775**
  transient (un-laundering integrity without a real probe parks the reference).
- End-to-end guard added to `gate_finalizer_test.exs`: a run output missing the
  calibration signal abstains and parks through the real `Finalizer.finalize!` path.

### A7d — empty acceptance suite fails the gate (dr1m.7) — `52a0401`
An acceptance suite that ran **zero tests** used to vacuously PASS. Closed at three
independent layers (toolchain producer, DB rerunner, gate-stage backstop), each keyed on
real per-test enumeration so status-only/stdout suites are unaffected. **Closes dr1m.7.**

## 2. Verified gate behaviour (before → after)
- Before: `TrustScore` always `:auto_accept`; abstain unreachable on the live path.
- After: a passed gate with an absent/`:invalid` calibration or absent/`:red` baseline
  **abstains → slice `:parked`**; a fully-green reference still auto-accepts at 0.925.
- The committed reference (`samples/beads_insight`) still auto-accepts through the live
  m1/m2/m3 production-loop pipeline (real pytest). No weight/threshold change.

## 3. The two Open Decisions — RESOLVED

### Decision 1 (baseline A2/A3): **do NOT force it fail-closed** — resolved, no machinery
Baseline regression is **already enforced by the `test_execution` gate STAGE** — a red
baseline *fails* the gate (it never reaches trust evaluation, since `TrustScore` only
adjudicates *passed* gates). So the baseline *trust signal* is **redundant**, and forcing
it fail-closed (the original A2/A3 plan) would **park the greenfield reference** (slice-1
has no green regression surface — the corpus is RED on the clean seed by design) for **zero
added safety**. Resolution: keep A1's behavior (a real `:failed` still abstains; absence
stays non-blocking). The heavy A2/A3 work (materialize DB suites + the OD19-style weight
renormalization) is **unnecessary** and is dropped. _No code change; no reference risk._

### Decision 2 (calibration A4/A5): real-base calibration is the right signal, but needs an **isolated base checkout**
`AcceptanceCalibration` *fabricates* `:valid` (its default runner never executes). Real
calibration — run the locked acceptance commands at base, `:valid` iff genuinely red-on-base
— is the one signal **no gate stage checks**, so it is the high-value flip. The corpus is
ready for it: `beads_insight`/`gx` are red-on-base → real `:valid`; `tasks_service` is
green-on-base but is **not on the reference trust path**, and for green-on-base corpora
`:invalid` is the *correct* signal (their acceptance tests don't prove new behavior) — a
corpus-quality finding, not a reason to fabricate.

**Attempted and reverted (this session), with a precise finding:** wiring the real runner
into the live `acceptance_calibration` station (`ToolchainRunner.runner` over `workspace_path`,
threaded via the assembler) was implemented and **broke the reference** — `m1` (slices 1–6)
passed, but `first_light_serial_driver_test` failed on **SLICE-007**: `reference_slice_007`'s
patch failed to apply (`report.py` Hunk #1 mismatch). Running `pytest` at base **in the live
workspace** pollutes it (caches/artifacts and/or source side-effects), and the cumulative
effect breaks the subsequent reference-patch application. Per the back-out discipline the
change was reverted (preserved in `git stash@{0}`).

**The fix (the real remaining work):** run base calibration in an **isolated base checkout**
(temp worktree / `git worktree add` or a clean copy at `base_commit`), never the live
workspace — exactly the "base-checkout seam" the recovered plan flagged. This is a
contained but real lift that wants a supervised iteration (it touches the workspace
lifecycle), so it is **not** forced unattended. The assembler already threads
`workspace_path`/`base_commit` to `implement`/`verify`; the calibration station needs the
isolated-checkout variant, not the live path.

## 4. Out of scope this branch (correctly deferred)
- **Integrity un-laundering** stays in `TrustEvidence.integrity/1` until D4/M4.8, atomic
  with the first real integrity probe (C1). Un-laundering it without a probe drops the
  reference to 0.775 → park.
- **Stream B** (real `replay_divergence` + `corpus_pass_rate` producers, OD19 hybrid
  committed-seed baseline) — needs the baseline machinery above.
- **Streams C/D/E/F** (integrity probes, hermetic gate, all-14-stages, static-stage
  MutantGauntlet) — later milestones.

## 5. Safe next steps (no corpus surgery, no live agent)
- Resolve the §3 Decisions, then land A2/A3 and A4/A5 with the base-checkout seam.
- Test/quality hardening: first `PlanRunner.run!/2` tests; re-enable Dialyzer; reconcile
  the ROADMAP/HANDOFF/tracker milestone narratives.
