# Session Handoff — 2026-06-20

> Compact handoff for the next agent/session. This is a **pointer doc** — the
> deep context lives in the artifacts referenced below; read those, don't expect
> this file to re-derive them.

## What just happened (TL;DR)

**First Light landed.** Conveyor now takes a real human plan and drives it
end-to-end through the width-1 synchronous loop to **gate-verified working
software**, and every link is independently proven:

- **M1a** — a real 7-slice plan reaches a real gate-pass through the loop.
- **M4** — the gate is proven honest (reference PASSES, 3 behavioral mutants
  FAIL, `false_pass = 0`).
- **Codex** — the live agent built the whole CLI from a stub workspace + a brief;
  its diff passed real pytest (16 green) and the gate (`gate_passed`, `findings []`).
- **Diff-scope** — bulletproofed: Codex changed exactly 9 files, all under
  `src/br_insight/` (`model.py`/`tests/`/golden untouched), reproducible ×2 — it
  *implemented* the code, it did not tamper.

Shipped as **PR #8 → `main`**: https://github.com/robertguss/software-factory-ai/pull/8
(13 `first-light` commits on branch `feat/first-light-m0-beads-insight`).

## Pick up here (the next thing)

**M1b productionization.** First read the master context doc (it has the full
build map, decisions, and gotchas), then start M1b:

1. **Read first:** `docs/2_implementation_plans/00-FIRST-LIGHT-HANDOFF.md` (§8 =
   the M1b build map; §8.0 = live status; §9 = the bet-trio specs).
2. **The keystone:** build `Conveyor.Planning.RunSpecAssembler` (lib) — port the
   test-only `BridgeFixtures` chain into `lib/` and emit a **self-describing**
   station_plan (embed `"module"` per station so `RunSlice` resolves it with no
   test opts — see `lib/conveyor/run_slice.ex:132`). This is collision-free
   (additive lib, no eval edits).
3. **Then per-slice gate-scoping** — ⚠️ this needs a `test-selection` change to
   `lib/conveyor/eval/toolchain_runner.ex` (`run_pytest` runs a fixed all-tests
   argv). That file is **eval-shared and the other terminal is actively editing
   it** — coordinate ownership with the human before touching it.
4. Then **M2** (`SerialDriver`, all 7 slices) → loop-closers (`AttemptLoop` +
   `Recovery.ReworkSynthesizer`, specs in handoff §9) so it iterates when the
   agent doesn't one-shot.

## Decisions waiting on the human

- **PR #8 scope:** the branch carries 3 of the eval terminal's `feat(eval)`
  gate-context commits (`6a4c509`, `e830683`, `f3f33f0`) under the First Light
  work. Offered to isolate First Light onto a clean branch off `main` (via
  `git worktree`, non-disruptive) — awaiting the human's preference.
- **M1b station home:** the canonical production stations — duplicate into
  `lib/conveyor/stations/` or refactor the existing `lib/conveyor/eval/*_station.ex`
  (the latter touches eval-shared code). Decide with the human.

## Environment & state

- **Branch** `feat/first-light-m0-beads-insight` — pushed, working tree clean,
  PR #8 open to `main`. Shared with the eval terminal (use explicit pathspecs on
  commits; the human said commit at each checkpoint).
- **DB**: a `postgres:16` container `conveyor-pg` is up on host **:5433** (creds
  `postgres`/`postgres`, local-only — not sensitive). Run DB-backed tasks/tests
  with: `MIX_ENV=test PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost mix …`.
  Tear down with `docker rm -f conveyor-pg`.
- **Codex CLI** is installed + subscription-authed (`/opt/homebrew/bin/codex`,
  v0.141) — the live-agent path works.

## Gotchas (learned this session)

- **Per-slice scoping** ⇒ `ToolchainRunner.run_pytest` uses a fixed all-tests
  argv (plan argv is metadata only). Needs a test-selection opt (eval-shared).
- **Live agent + DB sandbox**: a multi-minute Codex run exceeds the default 120s
  `Ecto.Adapters.SQL.Sandbox` ownership timeout — use `ExUnit.Case` + a setup
  that sets `ownership_timeout: :timer.minutes(60)` (see the live test).
- **pytest pin**: `samples/beads_insight/requirements.lock` (and tasks_service)
  pin `pytest==9.1.0`, which doesn't resolve in a local venv (latest 9.0.3); CI
  has the pinned wheel. Don't "fix" the lock.
- **`plan_lint` `missing_hard_constraint`** is cosmetic (the schema forbids the
  `constraints` array the linter wants); `plan_audit` is still `handoff_ready`.

## Key artifacts (read these — not duplicated here)

- **Master context:** `docs/2_implementation_plans/00-FIRST-LIGHT-HANDOFF.md`
- **The plan:** `docs/2_implementation_plans/PHASE-2.5-FIRST-LIGHT-SYNCHRONOUS-LOOP-BEADS-INSIGHT.md`
- **Strategy / ADRs:** `docs/BRAINSTORM.md`, `docs/adrs/`, `droid-wiki/`
- **Forcing-function target:** `samples/beads_insight/` (plan + scaffold +
  reference solution + canary mutants)
- **Proof tests:** `test/conveyor/eval/beads_insight_golden_thread_test.exs`
  ($0, CI-safe, discrimination) and `…/beads_insight_codex_live_test.exs`
  (`:live_agent`, the Codex build + diff-scope)
- **PR:** https://github.com/robertguss/software-factory-ai/pull/8
- **Cross-session memory:** `~/.claude/projects/-Users-robertguss-Projects-startups-software-factory-ai/memory/first-light-sync-loop-plan.md`

## Conventions (enforced — see root `AGENTS.md` + `droid-wiki/`)

Determinism boundary (conductor owns state/policy/evidence/verdicts; agents own
judgment). **TDD** (write the failing test first). `br` for work tracking, never
`bd`. `@N` schema versioning. `mix format --check-formatted` + `credo --strict` +
`dialyzer` + warnings-as-errors gate CI. Never weaken tests/contracts to pass a
gate; never let the code-writer author its own tests.

## Suggested skills for the next session

- **`br`** — track M1b/M2 work items in beads (`.beads/`), the repo's source of
  truth for implementation work.
- **`code-review`** — review the M1b diff (and PR #8) before merging.
- **`verify`** / **`run`** — confirm the loop still drives a plan to a gate-pass
  after M1b changes (re-run the two `beads_insight_*` tests).
- The repo mandates **TDD** (root `AGENTS.md`) — author the failing test first
  for each new module (`RunSpecAssembler`, the stations).
