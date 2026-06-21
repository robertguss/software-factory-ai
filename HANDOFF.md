# Session Handoff — 2026-06-21

> Compact pointer doc for the next session. The deep context lives in the
> referenced artifacts (the `br` issues, the ADRs, the PR) — read those; this
> file just orients you and tells you the next thing to do.

## What just happened (TL;DR)

**Fresh-eyes merge-readiness audit of PR #10** (`worktree-next-phase`, 36 commits
vs `main` = first-light loop + the raw-leverage **ADR-23–27** program). Nothing
was changed in the code — this was a review + independent validation pass.

Empirically validated (not just claimed):

- **Core suite green** under the PR's exact claim: `mix test --exclude eval` →
  **851 passed, 0 failures**. Compile `--warnings-as-errors`, `mix format`, and
  `mix credo --strict` are all clean.
- **ADR-23 reliability engine works end-to-end** — proven three ways:
  - **$0 docker** (`integrity_discrimination_docker_test`): hermetic→`:accepted`,
    network-open→`:abstained`+`:parked`, src-rewrite→`:abstained` (3/3 real asserts).
  - **Live Codex** (`beads_insight_codex_live_test`, 308s): Codex built Beads
    Insight (10 files, locked `model.py` untouched) and **passed the real gate**.
  - **Live multi-agent integrity** (`integrity_discrimination_live_test`, 380s):
    codex→trustworthy→`accepted`, pi→`needs_rework`; both →`abstained` on network-open.
- Claims audit (21 extracted): **17 true, 4 partial, 0 false.**

**Verdict: high-quality, but NOT "nothing left to do."** There is 1 must-fix in
the live gate path, a handful of should-fix bugs, some "the wording claims more
than is live" cleanup, and real coverage gaps. Mergeable after the must-fix +
wording pass; the rest can be fast-follow or are disclosed in-progress.

**Filed 17 review issues** under epic `software-factory-ai-dr1m`, all tagged
`pr10-review`, committed on this branch as `ad33d56`.

## Pick up here (the next thing)

```
br list --json --status open | (filter labels contains "pr10-review")
br show software-factory-ai-dr1m.1.1 --json     # the must-fix
```

1. **Fix the P1 must-fix `dr1m.1.1`** — the gate `:gate` AshStateMachine
   transition **always fails in the live path** (the production station sequence
   has no `:review` step, so the run_attempt never reaches `:reviewed`), and the
   blanket `rescue _error ->` in `lib/conveyor/gate/finalizer.ex:198-211` silently
   falls back to a raw status write — bypassing the state machine + lifecycle
   ledger and **masking all errors**. Outcomes still persist (why every test
   passes), so it's invisible without reading the code.
2. **Work the P2 should-fix bugs:** `dr1m.7` (verifier vacuous-pass on zero
   tests), `dr1m.8` (migration not safely reversible), `dr1m.1.2` (provenance-edge
   dedup), `dr1m.6.1` (operator-UX reporting), `dr1m.1.3` (vacuous baseline/
   calibration stations), `dr1m.1.4` (hardcoded `replay_fidelity`), `dr1m.3.1`
   (RaceConductor crash, ADR-25), `dr1m.4.1` (AmendmentRouter shape, ADR-26).
3. **Docs pass `dr1m.10`** — scrub overstated/stale claims (body + ADR-27 +
   moduledocs) so they match what's actually live.
4. **Decide `dr1m.9`** — AttemptLoop (retry/budget/rework) is **dormant**; the
   live path is single-attempt. Wire it or document it as deferred.
5. Then **merge PR #10**.

## Decisions waiting on the human

- **Merge strategy:** fix-then-merge (do P1 + P2 first) vs merge-now-and-
  fast-follow (accept the documented risks; only `dr1m.1.1` is a real concern).
- **`dr1m.9`** — ship the retry/rework loop (wire AttemptLoop into SerialDriver)
  or keep the live path single-attempt and mark it deferred.
- **Dormant ADR-24/25/26/27 items** (PlanFoundry, AmendmentRouter, RaceConductor,
  midflight) — confirm these stay roadmap (they have zero production callers; two
  carry bugs to fix *before* activation: `dr1m.3.1`, `dr1m.4.1`).

## Environment & state

- **Branch** `worktree-next-phase` = **PR #10** → `main`. Working tree clean
  except untracked `.conveyor/` (local test artifacts — ignore/don't commit).
  Last commit `ad33d56` (the filed issues); **not pushed**.
- **DB**: local Postgres on **:5432**; the superuser role is **`robertguss`**, NOT
  `postgres` (the old `:5433`/`postgres` container handoff is stale). Run tests:
  `PGUSER=robertguss PGPASSWORD=postgres PGHOST=localhost PGPORT=5432 mix test --exclude eval`.
- **Codex CLI** logged in via ChatGPT (`/opt/homebrew/bin/codex`, v0.141) — live
  agent path works. **OrbStack** docker running; runner image
  `conveyor/beads-insight-runner:local` is built (live/$0 docker tests run fast).

## Gotchas (learned this session)

- **"Core green" means `--exclude eval`, not `--exclude live_agent`.** The latter
  runs the `:eval` tests, which **fail environmentally**: `samples/tasks_service/
  requirements.lock` pins `anyio==4.14.0`, a version that **doesn't exist** on
  PyPI (max 4.13.0), so the pytest venv can't build. Not a code defect; tracked
  as `dr1m.12`. (`lift_duel_live` is blocked by the same pin.)
- **Tests pass despite the gate-transition bug** (`dr1m.1.1`) because they assert
  `outcome`/`state`, which the raw-write fallback satisfies — the bypass is masked.
- **Only the integrity trust signal is live**; baseline + calibration are vacuous
  stubs in production (`dr1m.1.3`). Abstain fires correctly on integrity (proven).
- **Dormant (zero prod callers):** AttemptLoop/AttemptBudget/RunSpecForge,
  PlanFoundry/CodexDrafter, AmendmentRouter, RaceConductor, ArtifactInputIndex.
- **Shell quirk:** `~/.zshrc` shadows `grep`/`test`/`ls`/`[` with custom tools —
  for scripting use `/bin/bash --noprofile --norc` or absolute `/usr/bin/...`.
- **Dialyzer** isn't a current gate (no project PLT; cached PLT is OTP28/1.19 but
  the repo runs OTP29/1.20). The PR adds 3 new warnings — `dr1m.13`.

## Key artifacts (read these — not duplicated here)

- **The review backlog:** `br` epic `software-factory-ai-dr1m`, label `pr10-review`
  (17 issues; `dr1m.1.1` is the must-fix). This is the durable record of the audit.
- **PR:** https://github.com/robertguss/software-factory-ai/pull/10
- **Strategy / ADRs:** `docs/RADICAL-LEVERAGE-IDEAS.md`, `docs/adrs/adr-23..27-*.md`,
  `docs/2_implementation_plans/RAW-LEVERAGE-PROGRAM-PLAN.md`, plus the ADR-23 and
  ADR-27 implementation plans in that dir.
- **Proof tests:** `test/conveyor/eval/integrity_discrimination_docker_test.exs`
  ($0, the cleanest ADR-23 proof), `…/beads_insight_codex_live_test.exs` and
  `…/integrity_discrimination_live_test.exs` (`:live_agent`, real spend).
- **Cross-session memory:** `~/.claude/projects/-Users-robertguss-Projects-startups-software-factory-ai/memory/`
  (`conveyor-radical-leverage-thesis.md`, `first-light-sync-loop-plan.md`).

## Conventions (enforced — see root `AGENTS.md` + `droid-wiki/`)

Determinism boundary (conductor owns state/policy/evidence/verdicts; agents own
judgment). **TDD** (failing test first). `br` for work tracking, never `bd`. `@N`
schema versioning. `mix format --check-formatted` + `credo --strict` + warnings-
as-errors gate CI. Never weaken tests/contracts to pass a gate; never let the
code-writer author its own tests.

## Suggested skills for the next session

- **`br`** — work the `pr10-review` backlog under epic `software-factory-ai-dr1m`.
- **`verify`** / **`run`** — after fixing `dr1m.1.1`, re-run the docker + (optionally)
  live proof tests to confirm the gate still produces accepted/abstained/parked.
- **`code-review`** — review the fix diffs before merging PR #10.
- **TDD is mandated** — write the failing test first for each fix (the coverage
  issues `dr1m.6.2`/`.1.5`/`.11` already mark where tests are missing).
