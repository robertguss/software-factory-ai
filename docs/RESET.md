# The Reset — 2026-07-02

**Status:** ratified by the owner (Robert), 2026-07-02. **Supersedes** all
prior direction where they disagree, including ROADMAP execution updates and
any open bead. **Recovery point:** git tag `pre-reset` (everything deleted by
this reset is recoverable from it).

## What Conveyor is

> Conveyor is Robert's personal overnight software factory: he hands it a real
> plan at night, a trust gate decides what merges, he wakes to verified work.

Everything in this repository either serves that sentence or is deleted.

## Why this reset exists

In its first 17 days (2026-06-15 → 2026-07-02) the project accumulated 832
commits, ~59k lib LOC, 50 mix tasks, and 793 beads — with AI driving most
feature ideation. The result was a healthy machine pointed at nothing:

- **A ghost factory.** ~122 modules / ~15.4k LOC (28% of lib) were reachable
  only from their own tests — built speculatively, wired into nothing a human
  runs. 14 gate stages built, 7 wired; 6 agent backends, 3 reachable; a dead
  async `Jobs.*` mirror of the station layer.
- **A backlog treadmill.** Bead creation outpaced closure 1.19:1 lifetime; the
  open pile grew every single week (90 → 113 → 126). Recent beads were almost
  entirely self-referential — the factory filing work about its own triage,
  calibration, and gate surfaces.
- **No real workload, ever.** Every run targeted synthetic calibration samples
  (`beads_insight`, `gx`, `tasks_service`). The roadmap's own exit bar (a real
  ≥20-slice unattended plan) was never attempted.
- **The tell.** The final pre-reset commit added a prompt instructing an agent
  to "drive the open-bead backlog to zero" — AI clearing a backlog AI wrote,
  with the human fully outside the loop, in a project whose entire thesis is
  keeping the human's judgment in it.

The diagnosis: the code never failed — 1,456 tests were green on reset day.
The **process** failed. AI became both the customer (filing beads) and the
builder (closing them), and the owner drifted from customer to spectator.
Conveyor became its own strongest evidence that ungoverned AI-driven work
sprawls.

## The verdict

**No rewrite.** The hard-won core — serial loop, trust gate with calibrated
abstain, evidence ledger, rework/park/resume — works and is the expensive 30%.
A rewrite would re-run the failed experiment with less test coverage, because
the failure was process, not code. Instead: keep the engine, delete the ghost
factory, and re-install the owner as the only customer.

## Standing rules (the actual fix)

1. **No bead without a run.** A bead may be filed only from (a) explicit owner
   intent, or (b) a gap observed in a real Conveyor run (gap log / park /
   escape). AI agents must never file beads from their own improvement ideas.
2. **The owner authors intent.** Plans, priorities, and merge decisions are
   Robert's. AI builds; it does not decide what to build.
3. **Run before build.** Factory-improvement work happens in response to real
   runs, not ahead of them. Every factory change should cite the run or gap
   that demanded it.
4. **Keep the discipline that worked.** Strict TDD, the five-check gate
   (format, compile with warnings-as-errors, tests, credo, dialyzer), honest
   evidence conventions. They are why this reset was cheap.

## The four moves

- **Move 0 — Stop the treadmill.** Delete `implement-all-beads-prompt.md`.
  Backlog amnesty: mass-close all open and deferred beads as archived
  hypotheses (recoverable in tracker history); they were written by nobody who
  wanted them. New work enters only under the standing rules.
- **Move 1 — Amputate the ghost factory.** Delete the test-only modules and
  their suites — the dead `Jobs.*` mirrors, workbench, chronicle, battery,
  cassette islands, contract critic, test architect, unreachable agent
  backends, unwired gate stages, speculative audits. Rule: if the next real
  milestone does not call it, it goes; git remembers everything (tag
  `pre-reset`).
- **Move 2 — Feed it one real thing.** First target: a **greenfield personal
  project Robert genuinely wants**, in Python (proven toolchain) or Elixir
  (home stack; requires hand-building the Elixir toolchain adapter first).
  Not a calibration sample — output he would actually merge and use.
- **Move 3 — Demand-driven everything else.** The former M4/M5/M6 remainders
  (unwired stages, in-factory decomposition, sentinels) are built only when a
  real run parks on their absence.

## The exit bar (replaces ROADMAP §4)

> **Conveyor built [the first target] overnight, and Robert merged it.**

Then, staged: a work-shaped greenfield internal tool → brownfield day-job
work. **Hard precondition for any day-job code:** employer AI/IP policy
cleared in writing first. No work code enters this system before that.

## Cut from the vision (not deferred — cut)

- **Cross-slice fleet parallelism** (Track B / M7 / the dormant Oban
  substrate). The owner runs on subscription plans — rate-limited,
  serial-shaped. Width-1 is not a phase; it is the product's identity. If that
  economic reality ever changes, this decision can be revisited from the tag.
- **The five-stack toolchain matrix.** Build exactly the toolchain the current
  target needs, one at a time.
- **"Others use it."** Frozen until Conveyor builds the owner's projects
  nightly for a month. The honest OSS story ("I use this every night") writes
  itself afterward.
- **The speculative eval empire** (lift duels, sentinel tournaments, golden
  threads). Kept: the gate-honesty chain (MutantGauntlet → scorecard gate) —
  it guards the core promise.

## What is kept (the engine)

The wired serial loop and its discipline: `mix conveyor.author` → plan →
stations → 7-stage trust gate (with real calibrated abstain) → evidence
ledger → rework/park/skip → resume → `mix conveyor.run_view` / triage /
digest. Plus the qualification/policy/budget/emergency-stop enforcement on the
live path, the DB-native task graph, and the sample-based gate-honesty evals
that keep the gate honest.

## Provenance

This charter came out of a fresh-eyes assessment and owner Q&A on 2026-07-02
(commit `602d9b6` was HEAD). Evidence: repo inventory and reference scan, git
and beads archaeology, and a green full-suite run (1,456 tests). The
pre-reset state — code, backlog, and roadmap — is preserved at tag
`pre-reset` and in tracker history.
