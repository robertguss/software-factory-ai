# Session Handoff — Conveyor (next up: M3 Phase 2 — live stress on hand-authored plans)

> Written 2026-06-22 for a fresh agent starting with a clean context window.
> **Previous session: M3 shipped + merged (PR #15), then validated LIVE on Codex.**
> **Next session's focus: Phase 2 — put the loop through its paces on NEW hand-authored plans.**
> This doc orients you; it does not duplicate the ROADMAP, ADRs, PRs, commits, or the
> auto-loaded memory — it points at them. Read the referenced sources before acting.

---

## 1. Read these first (source of truth — do not re-derive)

- **Auto-memory** (`MEMORY.md` → `conveyor-roadmap-and-state.md`) — has the full M3 + **M3 LIVE
  VALIDATION** write-up (survivability, findings, token spend). Start there.
- **`ROADMAP.md`** (v2) + **`ROADMAP-REVIEW.md`** — the milestone spine. M3 = epic `9z4r`.
- **`HUMAN.md`** (Robert's operating manual — auto-loaded) and `~/.claude/CLAUDE.md` (global, incl.
  the notification webhook — **token lives there; never inline it**).
- **`br`**: `br ready`, `br show <id>`, `br list`. New this session: `plan-schema-work-deps-2ho5`,
  `m6-crash-recovery-bzkr`, `9z4r.1`.
- **PR #15** (merged) = M3 skip-and-continue + reset-on-park. Read its body + the commits on `main`.

---

## 2. Where things stand (2026-06-22)

**M0–M2 ✅, M3 ✅ done + merged (PR #15), and M3 survivability proven LIVE.** All M3 code on `main`.

M3 delivered: **skip-and-continue** over the dep subgraph (a parked slice no longer halts; dependents
skip; new `:partial` status) + **lean reset-on-park** isolation. Adversarial review caught a data-loss
blocker (first-slice reset) which was fixed. See PR #15.

### The live validation (the headline of last session)
Robert: *"put it through its paces using Codex and live token spend."* **5 live `mix conveyor.run
--adapter codex`** runs of the 7-slice Beads-Insight plan through the production loop:

- **SURVIVABILITY = 5/5** — every run terminated cleanly, unattended, zero halt/hang. **3 green-complete**
  (`:passed`, first_pass 1.0), **2 survived-park** (`:partial`).
- **Agent green-rate = 3/4 clean runs (~75%)** — run #2's loader was a genuine stochastic Codex
  gate-failure (NOT a timeout — Codex was responsive) that bounded rework couldn't recover → parked →
  cascade-skip → `:partial`. The M2 watchdog + M3 skip-and-continue absorbed it cleanly.
- **Induced failure proven LIVE** — an unsatisfiable locked test (`assert 1 == 2`) on velocity (SLICE-005):
  Codex built 001-004 green, velocity parked (`acceptance_locked_failed`), 006-007 skipped → `:partial` (4/7).
- **Token spend now visible** — ~**13.7M tokens / ~$18.57 est / ~570k tokens per slice** (estimated at
  configured rates; actual marginal cost ~$0 on Robert's $200 ChatGPT/Codex sub).
- **Bar chosen by Robert = SURVIVABILITY** (the loop is reliable even when the agent isn't), NOT strict
  all-green. Honest caveat: "green" here = passes the 4-stage gate; **M4** is what makes green
  false-pass-resistant.

---

## 3. Findings from the live validation (carry these)

1. **Token spend was dropped before the DB write** → **FIXED** on branch `feat/codex-token-observability`
   (commits `7c41004` token fix + `c1106a8` tracker). Adapter-test-validated + confirmed on a real run.
   **NOT pushed / not PR'd** (Robert defers PR timing). **Action: PR this branch** (`gh pr create`)
   when Robert says — it's a clean, validated win.
2. **`conveyor.plan@1` schema forbids `work_dependencies`** [`br plan-schema-work-deps-2ho5`] — PlanRunner
   *reads* it and the work_graph fully supports branches, but the JSON schema has
   `additionalProperties:false`, so `PlanContract.load` rejects any plan that declares deps → forced into
   the linear `chunk_every` fallback. **This BLOCKS Phase 2** (hand-authored plans can't express
   independents/branches) and the richest live skip-and-continue demo. **Fix first** (add an optional
   `work_dependencies` array `{from,to,kind}` to the plan@1 schema; low-risk — consumer already exists).
3. **`reference_solution` rework re-applies the same canned patch** → "already applied" crash (the
   carry-forward follow-up; reference-adapter-only — live Codex writes fresh each attempt, so it's fine
   on the `--adapter codex` path).

---

## 4. Phase 2 — the next work (your job)

**Goal (Robert's choice): stress the live loop on NEW hand-authored plans to find where it breaks.**
M3's survivability bar is met; Phase 2 is exploratory hardening on fresh substrate.

**Do this in order:**
1. **Land the `work_dependencies` schema fix** (`plan-schema-work-deps-2ho5`) — prereq for any
   branching plan. Then you can finally show **independents proceeding past a park** LIVE (the M3
   headline), which the linear fallback can't.
2. **Author 1–2 NEW `conveyor.plan@1` plans** in a *different* domain/shape (decomposition is M5, so you
   hand-write the contracts). Keep them **Python + pytest acceptance** (the gate's `test_execution` stage
   + the venv builder expect that). Mirror `samples/beads_insight/`'s structure (`conveyor.plan.yml` +
   `src/` + `tests/` + `requirements.lock` + locked acceptance tests).
3. **Run them live** (`--adapter codex`), measuring **survivability** (terminate clean) + green-rate +
   token spend. Induce failures (unsatisfiable locked test) to exercise skip-and-continue on a real
   branch. Report findings (expect to surface more gaps — that's the point).

**Honest stance to keep:** live Codex is stochastic (~75% green on the EASY Beads task). Don't chase
"all-green"; certify **survivability** + report green-rate as the agent-reliability signal. A
subtly-wrong-but-tests-pass slice still slips through until **M4** activates the gate.

---

## 5. Build / verify / run commands

```bash
mix test --exclude eval --seed 0                 # default CI suite (~868 tests)
mix test <files> --include eval --seed 0         # real-pytest :eval tests
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors

# LIVE run recipe (codex is authed to Robert's ChatGPT sub; ~15-45 min for 7 slices):
WS="${TMPDIR}/conveyor-live-$(date +%s)"
rsync -a --exclude .venv --exclude .pytest_cache --exclude __pycache__ --exclude .git \
  samples/beads_insight/ "$WS/"
git -C "$WS" init -q -b main && git -C "$WS" add -A \
  && git -C "$WS" -c user.email=c@e.test -c user.name=c commit -qm base
mix conveyor.run "$WS/conveyor.plan.yml" --adapter codex --workspace "$WS"   # live Codex
mix conveyor.run "$WS/conveyor.plan.yml" --adapter reference_solution --workspace "$WS"  # $0 harness smoke

# Induce a deterministic LIVE park (unsatisfiable locked test):
python3 -c "p='$WS/tests/test_velocity.py'; s=open(p).read(); \
  s=s.replace('def test_weekly_buckets_as_of():\n','def test_weekly_buckets_as_of():\n    assert 1 == 2\n',1); \
  open(p,'w').write(s)"
```
- The gate auto-builds a venv from the workspace's `requirements.lock` (cached in `$TMPDIR/conveyor_eval_venv_*`).
- `mix conveyor.run` exits **non-zero on `:partial`** (correct) — don't `set -e` a run-loop on it.
- Token/cost are now on `agent_sessions.tokens` / `.cost_estimate` (query the dev DB).
- Run state lands in the **dev DB** (real Ash records). Temp workspaces accumulate in `$TMPDIR/conveyor-*`.

---

## 6. Git state to reconcile

- `main`: M3 merged (`a1e4db4`). Clean.
- `feat/codex-token-observability`: **2 commits ahead, local-only** — token fix (`7c41004`) + tracker
  chore (`c1106a8`). **Ready to PR** when Robert asks. (The working tree is currently on this branch.)
- M6 durable crash-recovery is filed (`m6-crash-recovery-bzkr`); M3 resumability was folded into it.

---

## 7. How to work with Robert (see `HUMAN.md`)

- **True partner, not a yes-man** — push back; hunt for flaws; be the brake on complexity.
- **Planning/deciding → tight & interactive, one question at a time** until ~95% confident. **Executing →
  autonomous, milestone-by-milestone**, green commit per milestone, brief pause at boundaries.
- **Truth over optimism** — verify, don't assert (last session caught a data-loss blocker + a vacuous
  test this way; the live runs surfaced real findings, not a green-rubber-stamp).
- **Cost:** Robert is **not** worried about Codex spend (his $200 sub) — he WANTS live runs. Track
  cost-per-verified-outcome as a metric, not a constraint.
- **Git discipline:** don't commit/push/PR unless asked; branch off `main`; commit trailer ends with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; PR bodies end with the
  Claude Code generation line.
- **Notifications:** on done/blocked/needs-input, POST the getmoshi webhook in `~/.claude/CLAUDE.md`
  (this session's plugin redirects Bash `curl` — send via the context-mode sandbox / `ctx_execute`).
  **Token is in CLAUDE.md — never copy it into a file.**

**First action next session:** re-orient from the `conveyor-roadmap-and-state` memory (has the live
results) + `br ready`, confirm PR #15 is on `main`, then start Phase 2 by landing the
`work_dependencies` schema fix (`plan-schema-work-deps-2ho5`) before authoring the new plans.
