# Session Handoff — Conveyor (Phase 2 DONE: work_dependencies + a 2nd live plan)

> Written 2026-06-22 for a fresh agent starting with a clean context window.
> **This session: Phase 2 MERGED to `main` (PR #16 schema+gx, PR #17 codex token fix).**
> The `work_dependencies` schema gap is fixed and the loop was proven LIVE on a NEW
> hand-authored branching plan (`gx`) — including **independents proceeding past a
> park** (the M3 headline the old linear fallback couldn't do).
> This doc orients you; it points at the sources — read them before acting.

---

## 1. Read these first (source of truth — do not re-derive)

- **Auto-memory** (`MEMORY.md` → `conveyor-roadmap-and-state.md`) — has the full **PHASE 2**
  write-up (schema fix, the `gx` sample, the 4-agent pre-flight review, the LIVE results).
  Start there.
- **`ROADMAP.md`** (v2) + **`ROADMAP-REVIEW.md`** — the milestone spine. M0–M3 ✅; next is **M4**
  (activate + finish the gate — the heaviest, net-new verifier completion).
- **`HUMAN.md`** (auto-loaded) + `~/.claude/CLAUDE.md` (global; notification webhook token —
  **never inline it**).
- **`br`**: `br ready`, `br show <id>`. New this session: `q8dz`, `r7wa`, `hx41` (review follow-ups).
- **`samples/gx/`** — the new sample. Mirror of `samples/beads_insight/` structure, different
  domain (directed-graph algorithms) + a real branching `work_dependencies` graph.

---

## 2. Where things stand (2026-06-22)

**M0–M3 ✅. Phase 2 ✅ + MERGED** — the `work_dependencies` schema gap is fixed + a 2nd
hand-authored plan ran live through the production loop. **Both branches merged to `main`:
PR #16 (schema + `gx` sample) and PR #17 (codex token-spend persistence).** main green —
default suite **874**.

### What was built + proven this session
- **Schema fix** (`plan-schema-work-deps-2ho5`, CLOSED): optional `work_dependencies:[{from,to,kind}]`
  in `conveyor.plan@1` + `PlanContract` **semantic validation** (refs/self-loop/cycle → clean
  `:invalid_work_dependencies` load error, not a mid-run `do_topo` crash). Also fixed 2 pre-existing
  cross-run temp-dir flakes (artifact-store + plan_contract tests; same class as `353827e`).
- **`samples/gx/`**: a 7-slice BRANCHING plan — loader (001) → 4 independent algo slices
  (degrees/toposort/components/cycles 002-005) → digest (006) → json+determinism (007). Stubs +
  RED locked tests + reference solution + `.conveyor/canary` per-slice patches.
- **`$0` pre-flight**: `reference_solution` loop `:passed` 7/7 deterministic. A 4-agent adversarial
  review (built venvs, mutated the reference) caught 3 real gaps BEFORE live tokens — all fixed
  (the determinism test was blind to its #1 target; json content unasserted; the semantic validation).
- **LIVE (`--adapter codex`), survivability 2/2:** happy path `:passed` **7/7** (first_pass 1.0);
  induced (broke SLICE-003's locked test) `:partial` **4/7** — 003 parked, **004/005 proceeded past
  the park**, 006/007 skip-cascade. Verified via `run_attempt.outcome` in the dev DB.

---

## 3. Findings to carry

1. **Token spend now persists** (PR #17 merged: `agent_sessions.tokens`/`.cost_estimate`). The gx
   live runs PREDATE the merge, so they have NO token numbers (estimate ~570k tok/slice from the
   beads baseline) — any FUTURE live run will record real spend. Query the dev DB to confirm capture
   on the next run; track cost-per-verified-outcome from here.
2. **Generator defense-in-depth gaps** [`q8dz`]: the digest golden is in NO `protected_path_globs`
   (a golden edit is blocked only single-layer by DiffScope); locked tests sit in `allowed_path_globs`
   and skew `max_files_changed`. Not blocking (gx live was fine) — real hardening for `run_spec_assembler`.
3. **`advisory` kind enum drift** [`r7wa`, low]; **`integration_order` is inert** in SerialDriver
   [`9z4r.1`, pre-existing]; **gx edge-case fixtures + a `$0` skip eval test** [`hx41`, low].

---

## 4. Next work — your call (recommend in this order)

> Both Phase-2 PRs are MERGED (#16, #17) — nothing pending to land.

1. **M4 — activate + finish the gate** (the next ROADMAP milestone; the load-bearing evidence step).
   Today "green" = passes the 4-stage gate; M4 makes it false-pass-resistant (wire dormant
   IntegritySentinel producers, real abstain, `corpus_pass_rate`/`replay_divergence`, network-isolated
   gate, extend MutantGauntlet to static stages). This is net-new verifier completion, not wiring.
2. **OR more Phase-2 stress** (cheaper, optional): a 2nd contrasting plan — a deep-PIPELINE shape
   (e.g. `calc`: tokenizer→parser→evaluator) to exercise a long cascade-skip, or a brownfield target.
   Robert deferred a 2nd plan this session (one done thoroughly).

**Honest stance:** live Codex is stochastic; certify SURVIVABILITY + report green-rate. gx happy path
hit 7/7 first-pass (the strengthened locked tests held), but don't assume that repeats — run N times
if you want a green-rate. A subtly-wrong-but-tests-pass slice still slips until **M4**.

---

## 5. Build / verify / run commands

```bash
mix test --exclude eval --seed 0                 # default CI suite (~874 tests)
mix test <files> --include eval --seed 0         # real-pytest :eval tests
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors

# $0 harness smoke (deterministic, no tokens) — gx or beads:
WS="${TMPDIR}gx-ref-$(date +%s)"
rsync -a --exclude .venv --exclude .pytest_cache --exclude __pycache__ --exclude .git samples/gx/ "$WS/"
git -C "$WS" init -q -b main && git -C "$WS" add -A && git -C "$WS" -c user.email=c@e.test -c user.name=c commit -qm base
MIX_ENV=dev mix conveyor.run "$WS/conveyor.plan.yml" --adapter reference_solution --workspace "$WS"

# LIVE (codex authed to Robert's ChatGPT sub; ~15-45 min for 7 slices):
MIX_ENV=dev mix conveyor.run "$WS/conveyor.plan.yml" --adapter codex --workspace "$WS"

# Induce a deterministic LIVE park (break a slice's locked test so no impl can pass):
python3 - "$WS/tests/test_toposort.py" <<'PY'
import re,sys; p=sys.argv[1]; s=open(p).read()
s=re.sub(r'(def test_topological_order_dag\(\):\n)', r'\1    assert 1 == 2\n', s, count=1)
open(p,'w').write(s)
PY
```
- `mix conveyor.run` exits **non-zero on `:partial`** (correct) — don't `set -e` a run-loop on it.
- Skipped slices stay `drafted` (nil outcome); parked = `needs_rework`; passed = run_attempt
  `outcome="accepted"` (slice.state stays `ready`). Query the **dev DB** for ground truth.
- The gate auto-builds a venv from `requirements.lock` (cached in `$TMPDIR/conveyor_eval_venv_*`).

---

## 6. Git state

- `main` (`a39ed69`): Phase 2 merged — **PR #16** (`feat/plan-work-deps-schema`: schema fix +
  semantic validation + 2 flake fixes + the whole `gx` sample) and **PR #17**
  (`feat/codex-token-observability`: token-persist fix, rebased to a single clean commit — its
  stale `c1106a8` HANDOFF/`.beads` edits were dropped as already-superseded). Clean, 874 green.
- The two merged feature branches still exist (local + remote); safe to delete.
- M6 durable crash-recovery filed (`m6-crash-recovery-bzkr`).

---

## 7. How to work with Robert (see `HUMAN.md`)

- **True partner, not a yes-man** — push back; hunt for flaws; be the brake on complexity.
- **Planning → tight & interactive, one question at a time; executing → autonomous milestone-by-milestone**,
  green commit per milestone, brief pause at boundaries.
- **Truth over optimism — verify, don't assert** (this session: the `$0` pre-flight caught a
  locked-path block + a vacuous determinism test before any tokens; the live skip-cascade was
  confirmed from `run_attempt.outcome`, not assumed).
- **Cost:** Robert WANTS live runs (his $200 sub); track cost-per-verified-outcome as a metric.
- **Git:** don't commit/push/PR unless asked; branch off `main`; commit trailer ends with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; PR bodies end with the
  Claude Code generation line.
- **Notifications:** on done/blocked/needs-input, POST the getmoshi webhook (token in `~/.claude/CLAUDE.md`
  — never copy it into a file).

**First action next session:** re-orient from `conveyor-roadmap-and-state` (has the Phase-2 results)
+ `br ready`; confirm `main` is current (Phase 2 already merged — PR #16/#17, nothing pending to
land); then start **M4** (activate + finish the gate). See §4 for the alternative (more Phase-2 stress).
