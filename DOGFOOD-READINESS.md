# Conveyor — Dogfood Readiness & Reality Check

**Date:** 2026-06-29 **Branch:** main **Method:** `reality-check-for-project`
(Phase 1 only — assess, do not generate new beads) + a 4-agent code/docs/bead
audit. **Companion docs:** `ROADMAP.md` (direction, source of truth),
`M4-PROGRESS.md` (gate detail), `STRATEGY.md` (product).

This document answers one question: **how far is Conveyor from being usable on a
real project** — take a medium plan, break it into work units, and have Conveyor
run it one-at-a-time, synchronously, to completion? It is a point-in-time
snapshot of _current state_, not a plan; for forward direction see `ROADMAP.md`.

---

## 1. Verdict (the distance)

**The engine you want already exists and runs.** This is the headline, and it is
better news than the 50 open beads suggest. The serial, autonomous,
run-a-plan-to-completion loop is wired, real, and invocable today with a single
command. The distance to dogfooding is **not a pile of unbuilt features** — it is
three much smaller things:

1. **One banked proof run** that has never been executed-and-recorded (`bd50`).
2. **Authoring friction** — breaking a plan into approved work units is manual
   and tedious today (no prose→work-unit step; ~40 CLI calls for a 20-slice
   plan).
3. **Two trust/safety caveats** you must either accept (for a sterile target) or
   close (for a real repo): no independent reviewer in the gate, and no
   blast-radius container.

Concrete distances, by ambition level:

| Goal                                                                          | Distance                                                                          |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Run a **small** plan (3–8 slices) on a **sterile/throwaway** target, attended, watching it work | **~now.** One focused session to author+run a sample. This _is_ the open `bd50`.   |
| Same, but **banked** as committed CI proof so it can't regress                | **+1 small task** (`gexs`).                                                        |
| **Trust** an accepted slice on real (non-sterile) code                        | **M4 remainder** — wire `reviewer_aggregation` + the network-isolated container.  |
| Run a **medium** plan (15–40 slices) synchronously, unattended overnight      | **M6 remainder** — drift detection + budget enforcement + parked-queue triage. The ≥20-slice live run is literally the M6 exit bar. |
| Parallel / fleet execution                                                    | Track B (M7) — explicitly out of scope for now, and you don't want it yet.        |

**The steer:** you are right to want to stop adding features and start using it.
The single most informative thing anyone can do next is **run a real agent
through the loop on a small real plan and watch what breaks** — and that has not
been done on record. Doing it will tell you what to build next from _evidence_
instead of from speculation. The 41-bead operator-trust/cockpit expansion
(`a3hf`) should wait behind that first run.

---

## 2. What actually works today (the engine)

One command drives an entire approved plan to completion. Verified by reading the
code (file:line evidence), not by trusting the docs:

```
mix conveyor.run <PLAN_ID> --adapter codex --workspace /path/to/sterile/target
```

`conveyor.run` → `PlanRunner.run_plan!` (`lib/conveyor/planning/plan_runner.ex:67`)
→ `SerialDriver.run!` (`lib/conveyor/planning/serial_driver.ex:90`). The driver
is a **width-1 serial loop over the whole approved work-graph**, and every link
in the chain is real:

| Capability                          | Status | Evidence                                                                                  |
| ----------------------------------- | ------ | ----------------------------------------------------------------------------------------- |
| Plan → executable work-graph        | REAL   | `plan_runner.ex:67-102` DB plan → `WorkGraphBuilder` → topo-sorted slices                 |
| Per-slice station pipeline          | REAL   | `run_slice.ex:41-59` ordered station run (ContextScout→…→Implement→Verify→RecordEvidence) |
| **Real agent execution**            | REAL   | `agent_runner/codex.ex:201-223` real `System.cmd` `codex exec --json` in a sandbox        |
| **Real verification**               | REAL   | `toolchain_runner.ex:161-173` real `pytest` via `System.cmd` (local) / docker             |
| 7-stage deterministic trust gate    | REAL   | `serial_driver.ex:50-58` (workspace, contract_lock, diff_scope, secret, policy, test, acceptance) |
| Ternary verdict (pass/fail/abstain) | REAL   | `gate/trust_score.ex`, `gate/finalizer.ex` — abstain band fires, fail-closed              |
| Rework-on-fail (≤3 attempts)        | REAL   | `attempt_loop.ex:45` `run_to_done!`, ON by default                                        |
| Skip-and-continue (no halt on park) | REAL   | `serial_driver.ex:99-105,171-173,207,217` — independents proceed past a parked slice      |
| Per-agent watchdog + reapers        | REAL   | `codex.ex:188-222` 15-min agent timeout (brutal_kill); slice 1h / run 8h reapers `serial_driver.ex:60-68` |
| Auto-advance to next slice          | REAL   | the driver loops the graph itself — no human kicking each unit                            |
| Git-commit-on-accept                | REAL   | `serial_driver.ex` resets/commits the workspace as it advances                            |
| Crash-resume from durable ledger    | REAL   | `application.ex:32-36` boot reconcile → `run_reconciler.ex:50-109` → `SerialDriver.resume!`|
| Clean exit-code semantics           | REAL   | `conveyor.run.ex:162-185` distinguishes `passed` / `gate_failed` / `parked_for_review`    |

Exercised end-to-end by `test/conveyor/m1_codex_production_loop_test.exs`. Agent
execution is real and is the **default**; the `fake` adapter is confined to the
hermetic `mix conveyor.demo` / `conveyor.ci` smoke path.

**For your stated goal — synchronous, one-at-a-time, run-to-completion — the
spine is built.** The Oban/conductor scaffolding that _looks_ like the engine is
stubbed (`worker_stub.ex:11-13`, `run_gate.ex:11-13`), but that only matters for
an always-on parallel service (Track B). For a synchronous run, the autonomy
correctly lives inside one blocking BEAM process.

---

## 3. The honest gaps (three rings)

### Ring 1 — Friction you hit immediately (the real near-term distance)

- **Authoring is manual.** There is no prose→work-unit decomposition on the run
  path. `mix conveyor.author "intent"` _looks_ like the front door but only emits
  a `conveyor.plan@1` JSON draft — it does **not** create DB tasks or hand off to
  `run` (`conveyor.author.ex:11-12`). So you hand-author every slice
  (`conveyor.task.create` / `.dep` / `.acceptance`) or hand-write the full plan
  JSON for `conveyor.plan.import`.
- **No bulk approve.** `run` refuses any `:drafted` slice; `task.lock` and
  `task.approve` are per-slice. A 20-slice plan is ~40 CLI invocations before
  `run` starts. (A small `approve-plan` command would be the highest-leverage
  ergonomic win for dogfooding.)
- **No banked proof.** The only committed end-to-end evidence is a
  `reference_solution` cassette (canned patch-applier), **not** a real-Codex run.
  The real-agent production run has never been executed-and-recorded (`bd50`) and
  there is no CI cassette test (`gexs`); the driver is still `Process.put`-stubbed
  in the operator tests. You would be the first real run on record.
- **Missing on-ramp docs.** `README.md` references `docs/dogfood/decomposition-aid.md`
  and `docs/dogfood/gap-log-template.md`, which **do not exist**.

### Ring 2 — Trust caveats (accept for sterile, close for real repos)

- **No independent reviewer in the loop — the load-bearing trust gap.** The
  production gate runs only _deterministic_ stages. `reviewer_aggregation` is
  **unwired** (`serial_driver.ex:48`) and the LLM reviewer's default
  **rubber-stamps `accepted/merge`** (`run_reviewer.ex:160-183`). A slice is
  accepted on tests + static checks alone — there is **no independent adversarial
  review of the author's work**. A subtly-wrong-but-tests-pass slice can pass.
  This is the project's own #1 anti-pattern ("do not let the agent that writes
  code author its own acceptance"). Part of `jmnt`/M4.
- **Gate is 7 of 14 stages.** Six static stages remain unwired (observed_risk,
  build_install, provenance_attestation, reviewer_aggregation, canary_freshness,
  code_quality_delta), plus the replay-divergence and corpus_pass_rate producers.
  "Green" today is not yet false-pass-resistant green.

### Ring 3 — Safety caveats (sterile targets only, for now)

- **No blast-radius container.** The run operates on an isolated _copy_ of the
  workspace (`conveyor.run.ex:104-124`) — filesystem-safe-ish — but there is no
  sandbox container. The code says it plainly: _"there is no blast-radius
  container yet … must never mutate a directory you care about."_ Default backend
  is `:local`.
- **Blind `git add -A` still live** (`serial_driver.ex:666`). The
  reset-to-base correctness piece landed (`serial_driver.ex:414`); worktree-per-slice
  + diff-policy-commit is deferred (`r6c5`, only matters at width>1).
- **Host prerequisites.** A real run needs git + docker + a logged-in `codex` CLI
  (subscription auth, no API key). `mix conveyor.doctor` enforces these. Without
  them, only `--adapter reference_solution` runs (plumbing tests, not real work).

---

## 4. "Open" ≠ "unimplemented" — the bead reality

You asked specifically whether what is open has actually not been implemented.
**Often it has.** Of 66 non-closed beads (50 open + 3 in-progress + the rest):

- **2 P1s are effectively DONE (false-open, closeable now):**
  - `p639` (watchdog/timeout) — the bead's premise ("`codex.ex` `System.cmd` has
    NO timeout") is now **false**: bounded timeout + brutal-kill + park-on-timeout
    is implemented at `codex.ex:188-222`, plus the M6 slice/run reapers.
  - `90v0` (skip-and-continue) — fully wired (`serial_driver.ex:207,217`); the
    bead note itself concedes "WIRING is implemented." Held open only as a stand-in
    for `9z4r`'s N-run evidence.
- **The epics are mostly tracking shells, not undone work.** `xs30` (M1),
  `vp73` (M2), `9z4r` (M3), `jwxp` (Track A), `dr1m` (Raw-Leverage) — their wiring
  has landed; they stay open for _exit-evidence_ (banked live runs), not new code.
- **The 3 in-progress beads are partial cores, not greenfield:** `dr1m.1`
  (ternary gate) live but calibration incomplete; `dr1m.2` (mid-flight check)
  built and tested but **zero live callers**; `dr1m.4` (plan amendment) **is**
  wired into `attempt_loop.ex` (its "follow-up: call route/2" comment is stale) —
  open only for the `dr1m.4.1` classifier bug.
- **~52 of 66 non-closed beads are feature-EXPANSION**, not required for a first
  synchronous run:
  - `a3hf` program — **41 beads**: cockpit/observability (17), spend-safety &
    pre-flight (12), gate dashboards (3), eval/de-risk corpus (3), persona/ops
    ergonomics (5), program epic (1).
  - EVAL / Track-B infra — **5**: `eval-011`, `eval-092/093/094`, `l290`.
  - Other deferrable — **6**: `dr1m.3`/`dr1m.3.1` (optional speculative-parallelism
    lever), `m6-crash-recovery-bzkr`, `9z4r.1`, `hx41`, `i9bz`.

**Genuinely-undone work that touches the serial loop is small:** `gexs` (CI
cassette test), `bd50` (execute+record the run), `jmnt` (the 6 remaining gate
producers, incl. the reviewer), and the optional ADR-25 race lever. Everything
else open is expansion or evidence-pending.

> ⚠️ Note: `p639` and `90v0` are candidates to close, but per project policy do
> not close a bead without verifying the fix and (for `90v0`) deciding where its
> N-run evidence requirement should live (likely fold into `9z4r`). Treat the
> "false-open" call as a recommendation to verify-then-close, not an instruction.

---

## 5. Roadmap status, oriented to dogfooding

From `ROADMAP.md` (Track A = serial autonomous; Track B = parallelism, gated
behind the §4 exit bar). Honest status:

| ID  | Intent                                            | Status        | Relevance to your goal                                         |
| --- | ------------------------------------------------- | ------------- | -------------------------------------------------------------- |
| M0  | Honesty cleanup                                   | ✅ done        | —                                                              |
| M1  | Join real agent to production loop (KEYSTONE)     | ✅ wiring; ⛳ proof pending | The proof = `bd50`/`gexs`. Your first run banks it.            |
| M2  | Wire dormant closers (rework, amendment)          | ✅ done        | —                                                              |
| M3  | Unattended small multi-slice plan (3–8)           | 🟡 wiring done; ⛳ N-run evidence pending | **Your first dogfood run _is_ this exit evidence.**           |
| M4  | Activate + finish the gate                        | 🟡 7/14 stages | **Trust.** Reviewer + container = the gap to trusting real-repo output. |
| M5  | Autonomous decomposition                          | 🟡 front door + dep-graph landed; prose→graph bypassed | **Not a blocker for you** — you break the plan into units manually. |
| M6  | Long-horizon autonomy + medium plan               | 🟡 survivability core landed | **Medium-scale.** Drift + budget + triage + the ≥20-slice run remain. |
| M7  | Cross-slice fleet (parallelism)                   | ⛔ pending      | Out of scope — you explicitly don't want it yet.              |
| M8  | Self-hosting capstone                             | ⛔ pending      | Far horizon.                                                   |

**Reading for your goal:** small-plan synchronous is M1+M2+M3, which is
_wired_ — the only missing piece is doing the run (M3 exit evidence = `bd50`).
Medium-plan synchronous unattended is M6, which needs the enforcement subset
(budget cap, emergency-stop, parked triage) but **not** the cockpit UI. Trust on
real code is M4 (reviewer + container).

---

## 6. Recommended shortest path to a first dogfood run

Ordered, smallest-first. Stop after step 2 and reassess — the run will reorder
everything below it.

1. **Run an existing sample end-to-end with a real agent, attended, and watch
   it.** This is the highest-leverage action in the whole project and it can
   happen now. Use a sample that already ships with a plan
   (`samples/beads_insight/` or `samples/gx/`). Prereqs: `mix conveyor.doctor`
   green (git + docker + logged-in `codex`). This _is_ `bd50`, and it doubles as
   the M3 exit evidence. Expect it to surface real friction/bugs that static
   analysis cannot.
2. **Bank that run as a committed CI cassette test** (`gexs`) so it can't
   regress and the M1 keystone is provable, not just claimed.
3. **(Optional, board hygiene)** Verify and close the false-open P1s `p639` and
   `90v0`; re-note `dr1m.4`'s stale comment.
4. **(For real-repo trust, when you get there)** Wire `reviewer_aggregation` into
   the production gate and stand up the network-isolated container — the two
   pieces that turn "runs" into "runs trustworthy." Part of `jmnt`/M4 + D1.
5. **(For medium unattended overnight, later)** The M6 enforcement subset only —
   budget cap + emergency-stop + parked-queue triage. **Not** the 17-bead cockpit
   UI.

**Explicitly defer:** the entire `a3hf` cockpit/legibility program (41 beads) and
the Track-B eval infra (5 beads) until after step 1 tells you which of them you
actually need. Building operator-trust dashboards before you have watched a
single real run is speculation; the run is the cheaper teacher.

A small ergonomic add — a bulk `approve-plan` command — would remove the ~40-call
authoring friction and is worth more to dogfooding than any cockpit panel.

---

## 7. Operator runbook (what works today)

```bash
# 0. Host prereqs (once): Postgres 16, git, docker, logged-in `codex` CLI.
mix setup
mix conveyor.doctor /path/to/sterile/target     # verifies docker + git + codex adapter

# Fast path: run a sample that already has a plan ------------------------------
#   (inspect samples/beads_insight/plan.md or samples/gx/plan.md first)
mix conveyor.seed_sample            # or: mix conveyor.plan.import <plan.json>
#   -> note the PLAN_ID (UUID)
mix conveyor.task.list --epic EPIC_ID       # confirm slices
mix conveyor.task.lock    --epic EPIC_ID --key SLICE-001   # first lock compiles the contract
mix conveyor.task.approve --epic EPIC_ID --key SLICE-001   # repeat lock+approve for EVERY slice
mix conveyor.run <PLAN_ID> --adapter codex --workspace /path/to/sterile/target
#   -> JSON: {"status":"passed"|"partial","disposition":"passed"|"gate_failed"|"parked_for_review", ...}
#   -> exit 0 = passed; nonzero = gate_failed or parked_for_review

# Read what happened
mix conveyor.run_view <RUN_ID>      # per-slice story
mix conveyor.parked                 # slices that abstained / need a human
# cockpit (read-only): GET /runs , live /parked
```

Authoring a plan from scratch (instead of a sample): `conveyor.plan.create` →
`conveyor.task.create` / `.dep` / `.acceptance` (per slice) → `.lock` → `.approve`
→ `conveyor.run`. Inputs live in `.conveyor/` (scaffolded by `conveyor.init`):
`config.toml`, `policies/*.toml`, `prompts/*`. Adapter auth = your `codex` CLI
subscription login.

---

## 8. One-paragraph answer

Conveyor's serial, autonomous, run-a-plan-to-completion engine is **built and
runnable today** — real Codex, real pytest, a 7-stage gate, rework, reapers,
skip-and-continue, and crash-resume, all driven by one `mix conveyor.run`
command. You are not far from using it: a first small dogfood run on a sterile
target is a single focused session away, and most of the 50 open beads are either
already-done, evidence-pending, or operator-trust expansion you can defer. The
two things that separate "runs" from "runs trustworthy on a real repo" are the
unwired independent reviewer and the missing sandbox container; the thing that
separates "small" from "medium unattended" is the M6 enforcement subset. Run it
first, then let the run tell you which of those to build next.
