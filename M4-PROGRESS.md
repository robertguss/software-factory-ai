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

## 3. BLOCKED — the producer fail-closed flips (A2/A3 baseline, A4/A5 calibration)

These are deferred, not skipped: landing them as-is would **park the known-good
reference** or require corpus surgery with unclear blast radius. Empirical findings
(see `scratchpad/CORPUS_FINDINGS.md`):

1. **Baseline (A2/A3).** No production code seeds `:baseline_regression` `VerificationSuite`
   rows; the reference's gate consumes the verify station's *injected* real-pytest result,
   while `BaselineHealth.run!` (the trust-signal producer) reads `[]` suites → vacuously
   `:passed`. Making it fail-closed on empty (`on_empty: :not_assessed`) would mark the
   greenfield **slice-1 baseline `:unknown` → park the reference** — slice-1 has no green
   regression surface (the corpus is RED on the clean seed by design). **Decision needed:**
   is baseline assessed at *base* (greenfield → declared-not-assessable, non-blocking) or
   *post-patch*? This is an unresolved Open Decision the recovered plan did not settle.

2. **Calibration (A4/A5).** `AcceptanceCalibration` currently **fabricates** `:valid`
   (its default runner never executes). Making it real over a base checkout is sound for
   `beads_insight` (acceptance tests are RED on base → `:valid`), **but `samples/tasks_service`
   is GREEN on base** (fully implemented; its red comes only from `mutants.json`). A real
   calibration would mark it `:invalid` → the spec's A4 says *stop and fix the corpus*, not
   flip. **Decision needed:** repair `tasks_service`'s locked acceptance tests to be
   genuinely red-on-base before the A5 flip. Also: the real runner needs a base-checkout
   seam wired into the `acceptance_calibration`/`baseline_health` station inputs
   (`run_spec_assembler.ex:109-113` only injects `blob_root`).

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
