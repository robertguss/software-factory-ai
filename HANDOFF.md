# Session Handoff — Conveyor (M4 trust-gate honesty PARTIAL — de-laundering + 7 live gate stages merged)

> Updated 2026-06-23 for a fresh agent starting with a clean context window.
> **Latest: the M4 trust-gate slice merged to `main` (PR #19 `m4-gate-honesty`,
> merge `3bca611`, 23 commits).** It is **partial by design** — the keystone
> de-laundering landed so **abstain now fires on the live path** (a passed gate
> with a missing/invalid trust signal parks the slice),
> calibration/integrity/replay are un-laundered, an empty acceptance suite fails
> the gate, and the production gate runs **7 required stages** (was 4). Phase 2
> (PR #16/#17) was already merged before this. **Read `M4-PROGRESS.md` for
> exactly what landed vs. what remains before treating any of it as done.** This
> doc orients you; read the sources.

---

## 1. Read these first (source of truth — do not re-derive)

- **`M4-PROGRESS.md`** (read first for the current gate status) — what landed in
  PR #19 and the explicit remaining M4 work (producers + the 6 unwired static
  stages).
- **Auto-memory** (`MEMORY.md`) — prior-session write-ups (Phase 2: schema fix,
  the `gx` sample, the 4-agent pre-flight review, the LIVE results).
- **`ROADMAP.md`** (v2; reconciled 2026-06-23) + **`ROADMAP-REVIEW.md`** — the
  milestone spine. **M0–M3 ✅; M4 🟡 substantially in progress** (the keystone
  merged, partial by design); M5 (decomposition) and M6 (long-horizon /
  crash-recovery) untouched. Trust `M4-PROGRESS.md` + the live code over any
  stale milestone-body text.
- **`HUMAN.md`** (auto-loaded) + `~/.claude/CLAUDE.md` (global; notification
  webhook token — **never inline it**).
- **`br`**: `br ready`, `br show <id>`. New this session: `q8dz`, `r7wa`, `hx41`
  (review follow-ups).
- **`samples/gx/`** — the new sample. Mirror of `samples/beads_insight/`
  structure, different domain (directed-graph algorithms) + a real branching
  `work_dependencies` graph.

---

## 2. Where things stand (2026-06-23)

**M0–M3 ✅. M4 (trust gate) 🟡 PARTIAL + MERGED (PR #19, merge `3bca611`).**
Phase 2 (PR #16 schema+`gx`, PR #17 codex token-spend) merged earlier. main
green — default suite **911** (+71 eval).

### M4 — what landed in PR #19 (the latest work; see `M4-PROGRESS.md` for the full breakdown)

- **De-laundered trust evidence** (`trust_evidence.ex`): absent signals fail
  closed (calibration→`:not_assessed`, baseline→`:unknown`,
  integrity→`not_assessed`, replay→`:baseline_absent`) — so the calibrated
  **`:abstain` band fires** on the live path (beads_insight SLICE-007 parks on a
  weak-acceptance calibration).
- **Real acceptance calibration** in an isolated base git-worktree
  (`acceptance_calibration.ex`); **`:local` integrity** requires the real
  `source_mutation` probe; **empty acceptance suite fails** the gate; **OD19**
  cold-start replay-weight renormalization (reference → 0.9118).
- **3 static gate stages wired live as required** (`serial_driver.ex`
  `@default_gate_stages` → **7 total**): workspace_integrity (+ a non-mutating
  head-tree producer), policy_compliance, acceptance_mapping. `MutantGauntlet`
  now discriminates the policy_compliance static stage.
- **Remaining M4** (tracked `br jmnt` + `dr1m.1`): real replay-divergence
  producer (`replay_fidelity.status` still hardcoded `"matched"`),
  `corpus_pass_rate`, the **6 unwired static stages** (each needs a producer),
  the docker hermetic/network-isolated gate.

### What was built + proven in Phase 2 (prior session — preserved as history)

- **Schema fix** (`plan-schema-work-deps-2ho5`, CLOSED): optional
  `work_dependencies:[{from,to,kind}]` in `conveyor.plan@1` + `PlanContract`
  **semantic validation** (refs/self-loop/cycle → clean
  `:invalid_work_dependencies` load error, not a mid-run `do_topo` crash). Also
  fixed 2 pre-existing cross-run temp-dir flakes (artifact-store + plan_contract
  tests; same class as `353827e`).
- **`samples/gx/`**: a 7-slice BRANCHING plan — loader (001) → 4 independent
  algo slices (degrees/toposort/components/cycles 002-005) → digest (006) →
  json+determinism (007). Stubs + RED locked tests + reference solution +
  `.conveyor/canary` per-slice patches.
- **`$0` pre-flight**: `reference_solution` loop `:passed` 7/7 deterministic. A
  4-agent adversarial review (built venvs, mutated the reference) caught 3 real
  gaps BEFORE live tokens — all fixed (the determinism test was blind to its #1
  target; json content unasserted; the semantic validation).
- **LIVE (`--adapter codex`), survivability 2/2:** happy path `:passed` **7/7**
  (first_pass 1.0); induced (broke SLICE-003's locked test) `:partial` **4/7** —
  003 parked, **004/005 proceeded past the park**, 006/007 skip-cascade.
  Verified via `run_attempt.outcome` in the dev DB.

---

## 3. Findings to carry

1. **Token spend now persists** (PR #17 merged:
   `agent_sessions.tokens`/`.cost_estimate`). The gx live runs PREDATE the
   merge, so they have NO token numbers (estimate ~570k tok/slice from the beads
   baseline) — any FUTURE live run will record real spend. Query the dev DB to
   confirm capture on the next run; track cost-per-verified-outcome from here.
2. **Generator defense-in-depth gaps** [`q8dz`]: the digest golden is in NO
   `protected_path_globs` (a golden edit is blocked only single-layer by
   DiffScope); locked tests sit in `allowed_path_globs` and skew
   `max_files_changed`. Not blocking (gx live was fine) — real hardening for
   `run_spec_assembler`.
3. **`advisory` kind enum drift** [`r7wa`, low]; **`integration_order` is
   inert** in SerialDriver [`9z4r.1`, pre-existing]; **gx edge-case fixtures + a
   `$0` skip eval test** [`hx41`, low].

---

## 4. Next work — your call (recommend in this order)

> Phase-2 PRs (#16, #17) and the M4 PR (#19) are all MERGED — nothing pending to
> land.

1. **Finish M4 — the gate is partially activated, not "next".** The keystone
   honesty already landed (abstain fires; calibration/integrity/replay
   un-laundered; the gate runs 7 required stages, not 4). **Remaining M4 work**
   (see `M4-PROGRESS.md` §3–4 + `br jmnt`): (a) the real **replay-divergence
   producer** — `replay_fidelity.status` is STILL hardcoded `"matched"`
   (`serial_driver.ex`; `dr1m.1.4`); (b) the **`corpus_pass_rate`** producer;
   (c) the **6 unwired static stages** (observed_risk, build_install,
   provenance_attestation, reviewer_aggregation, canary_freshness,
   code_quality_delta — each needs a producer, and an empty default would be
   advisory-theater, so they need real signals); (d) the **docker hermetic /
   network-isolated gate** + hermeticity probe; (e) the remaining deferred
   static mutants (contract_lock, run_check, code_quality).
2. **OR more Phase-2 stress** (cheaper, optional): a 2nd contrasting plan — a
   deep-PIPELINE shape (e.g. `calc`: tokenizer→parser→evaluator) to exercise a
   long cascade-skip, or a brownfield target. Robert deferred a 2nd plan this
   session (one done thoroughly).

**Honest stance:** live Codex is stochastic; certify SURVIVABILITY + report
green-rate. gx happy path hit 7/7 first-pass (the strengthened locked tests
held), but don't assume that repeats — run N times if you want a green-rate. A
subtly-wrong-but-tests-pass slice is now **caught further than before** —
abstain fires on the live path and parks a passed gate with a missing/invalid
trust signal — but coverage stays PARTIAL until the remaining M4 producers + the
6 static stages land (notably the real replay-divergence producer;
`replay_fidelity.status` is still hardcoded).

---

## 5. Build / verify / run commands

```bash
mix test --exclude eval --seed 0                 # default CI suite (~911 tests)
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

- `mix conveyor.run` exits **non-zero on `:partial`** (correct) — don't `set -e`
  a run-loop on it.
- Skipped slices stay `drafted` (nil outcome); parked = `needs_rework`; passed =
  run_attempt `outcome="accepted"` (slice.state stays `ready`). Query the **dev
  DB** for ground truth.
- The gate auto-builds a venv from `requirements.lock` (cached in
  `$TMPDIR/conveyor_eval_venv_*`).

---

## 6. Git state

- `main` is now at the **PR #19 merge (`3bca611`, `m4-gate-honesty`, 23
  commits)** plus this session's doc/tracker reconciliation commits — on top of
  Phase 2 (PR #16 schema/`gx`, PR #17 codex token-persist). Clean; deterministic
  suite **911** green, eval **71** green.
- The `m4-gate-honesty` branch was **deleted** (local + remote) after merge.
- M6 durable crash-recovery filed (`m6-crash-recovery-bzkr`). M4 trackers
  reconciled this session: `br jmnt` (Stream E gate-stage wiring) updated;
  `dr1m.7` + `dr1m.1.3` closed; `dr1m.1`/`dr1m.1.4` progress-commented (left
  open — producers/report-field remain).

---

## 7. How to work with Robert (see `HUMAN.md`)

- **True partner, not a yes-man** — push back; hunt for flaws; be the brake on
  complexity.
- **Planning → tight & interactive, one question at a time; executing →
  autonomous milestone-by-milestone**, green commit per milestone, brief pause
  at boundaries.
- **Truth over optimism — verify, don't assert** (this session: the `$0`
  pre-flight caught a locked-path block + a vacuous determinism test before any
  tokens; the live skip-cascade was confirmed from `run_attempt.outcome`, not
  assumed).
- **Cost:** Robert WANTS live runs (his $200 sub); track
  cost-per-verified-outcome as a metric.
- **Git:** don't commit/push/PR unless asked; branch off `main`; commit trailer
  ends with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; PR
  bodies end with the Claude Code generation line.
- **Notifications:** on done/blocked/needs-input, POST the getmoshi webhook
  (token in `~/.claude/CLAUDE.md` — never copy it into a file).

**First action next session:** re-orient from **`M4-PROGRESS.md`** (current gate
status) + the auto-memory + `br ready`; confirm `main` is current (PR #16/#17
AND M4 #19 already merged, nothing pending to land); then **continue M4** — the
keystone de-laundering + 7 live gate stages are in, so pick up the real
replay-divergence producer (`serial_driver.ex` still hardcodes `"matched"`),
`corpus_pass_rate`, and the 6 unwired static stages (§4 + `M4-PROGRESS.md`
§3–4). See §4 for the optional alternative (more multi-plan survivability
stress).
