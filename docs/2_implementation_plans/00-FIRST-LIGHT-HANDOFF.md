# 00 — First Light: Master Context & Handoff (READ THIS FIRST)

> **Purpose.** This is the durable, self-contained brief for the **First Light**
> initiative. A brand-new agent with zero prior context can read this one file
> and continue exactly as intended. It captures the strategy, the plan, the
> current state, the exact next build, the grounded specs, and every decision
> made so far. Written 2026-06-20.
>
> **If you read nothing else, read §1 (TL;DR) and §8 (the next build).**

---

## 1. TL;DR — where we are and what to do next

**The mission (the North Star):** make Conveyor take **a single human plan and
turn it into working software, driven SYNCHRONOUSLY (width 1, one slice at a
time, no fleet).** Parallelism is deliberately deferred. Build **on top of what
already exists** — Conveyor is a large, real system (~330 source files, ~50 Ash
resources, a deterministic 15-stage Gate, a real Docker sandbox, real Codex/Pi
agent adapters). We are NOT rewriting; we are wiring existing pieces into a loop
that closes.

**The honest current reality:** _"Conveyor can rigorously JUDGE software it
cannot yet BUILD."_ The **verifier** (Gate, mutation testing, anti-vacuity
sentinel, calibration, attestations) is world-class and runs for ~$0,
deterministically. The **generator seam is severed in production**: the only
end-to-end "run a slice through stations" path that exists is the **eval**
Golden-Thread one; the production stations are stubs; `ContractLock` / policy /
`ContextPack` are faked in the live loop; the real agent (Codex) is wired only
into the eval `AgentStation`.

**Forcing-function target:** a real, small, hermetic Python CLI called **Beads
Insight** (`br-insight`) over `.beads/issues.jsonl`. It exists already as a
plan + scaffold (see §7). **The thing under test is Conveyor, not the CLI** —
the CLI is the proof artifact; success is measured on the factory's behavior.

**The immediate next actions, in order:**

1. **Step 1 — lean plan course-correction** (revise
   `PHASE-2.5-FIRST-LIGHT-SYNCHRONOUS-LOOP-BEADS-INSIGHT.md`): fold the
   loop-closers into the milestone ladder as **prerequisites** (we discovered
   the synchronous loop **literally cannot terminate today** — see §6), install
   the **Genome** strategic thesis (§4), restructure the §10 backlog into the
   clusters in §10 here, add milestones **M2.5 (Back-Edge)** and **M7 (Sealed
   Verdict)**. Keep it tight — a course-correction, not a rewrite.
2. **M1 build — get SLICE-001 to a real green** through the **production** loop
   using the **ReferenceSolution** adapter first (decided — see §8, §12). $0,
   deterministic, isolates "is the loop wired right" from "can the agent solve
   it." Then swap in Codex.
3. Commit at each checkpoint (decided — §12) on branch
   `feat/first-light-m0-beads-insight`.

**The one-sentence strategy:** _fix the map (fast), then get the loop green on
one real slice — the bold/moat stuff (the Genome) compounds on top of a loop
that works and is vapor without it._

---

## 2. North Star & constraints (non-negotiable)

- **Goal:** one human plan → working software, **synchronously, width 1**.
- **Parallelism / fleet / dispatcher / merge-queue: DEFERRED** (ratified Law 27:
  implementation width = 1, merge manual). Ideas assuming width > 1 are out of
  scope for now.
- **Build ON the current architecture.** Name the real module you extend. No
  greenfield rewrites.
- **The determinism boundary is LAW.** The BEAM conductor owns state, policy,
  evidence, and gate verdicts; agents own drafting + judgment only. Projections
  (UI/CLI/reports) display authority, never create it. The 22 ADRs in
  `docs/adrs/` override `docs/BRAINSTORM.md` on conflict.
- **Separation of duties** at the resource level: the actor that writes code
  must never author its own acceptance contract or red-team tests.

---

## 3. What exists vs. what's severed (the precise gap)

**Real and reused unchanged:**

- `Conveyor.RunSlice.run!/2` + `Conveyor.Station.execute!/4` — the synchronous
  station-fold + wrapper (leases, idempotency, declared effects, artifacts,
  ledger, authority events). NOT eval code; the eval path uses them verbatim.
- `Conveyor.Jobs.RunGate.run_gate_only!/3` — the 15-stage Gate facade.
- ~50 Ash resources (`lib/conveyor/factory/`), the `Slice` + `RunAttempt`
  `ash_state_machine`s, the pure planning compiler (`lib/conveyor/planning/`,
  ~45 passes), `ContractForge`, `Readiness`, real Docker `Sandbox`, the `Codex`
  adapter, the cassette engine.

**Severed / stubbed (the work of First Light):**

- Production "stations" `Jobs.RunImplementer` / `Jobs.RecordEvidence` are
  `WorkerStub` no-ops; `Jobs.ContextScout` / `BaselineHealth` /
  `AcceptanceCalibration` are Oban shells that delegate to real modules but are
  **not wired as stations in the fold**.
- `ContractLock` / `RoleView` / policy / `ContextPack` are **stubbed in the
  live loop** (eval path fakes them with `sha256:bridge` digests).
- The real agent (`Codex`) is wired only into the **eval** `AgentStation`.
- **The loop cannot terminate** (see §6) — there is no multi-attempt conductor.

**Five structural superpowers (the strategic moat basis — unique because nobody
else built a deterministic, content-addressed, event-sourced, contract-first
factory):**

1. A Gate that judges **recorded evidence reproducibly, standalone**
   (`run_gate_only!/3` over a dossier; 15 stages incl. mutation,
   `IntegritySentinel` anti-vacuity, `acceptance_mapping`, calibration, canary,
   in-toto `provenance_attestation`).
2. **Content-addressed, event-sourced, cassette-replayable** history
   (`Cassettes`/`ReplayEngine`; generation-surface vs evaluation-surface split;
   `AuthorityEvents` + `Ledger`; replay the past for ~$0).
3. A **contract-first compiler with locked interfaces + a derivation graph**
   (`ContractForge`/`Critic`; `InvalidationPreview`/`ImpactPreview`/selective
   recompilation; `PlanAmendmentProposal`).
4. The **determinism boundary as law + separation of duties** (a real safety
   argument).
5. The **judge ≫ generator asymmetry** — the weakness IS the wedge.

---

## 4. The strategic thesis (the profound synthesis) — "verifier as product" + the Genome

**Conveyor is not just another coding agent (that race is commoditizing). Its
defensible product is the TRUST/VERIFICATION layer for AI-written software. Lead
with the verifier.**

The ~200 ideas we generated collapse into **one asset and one loop**:

- **The Genome** — a content-addressed, gate-verified graph of
  `intent ↔ code ↔ verdict ↔ outcome` that accretes on every run. Git stores
  _what changed_; the Genome stores _why it's correct, what it's for, what was
  rejected, and how it has failed here before_, each edge ratified by a
  deterministic gate verdict (evidence, not vibes).
- **The flywheel:** the synchronous loop **generates** the Genome; the Genome
  **makes the loop succeed more often** (better context, failure memory, learned
  routing). A competitor with a better base model still starts from zero scar
  tissue on your codebase. **The moat travels with the corpus, not the model.**

This is the accretive, disruptive thesis — and it is grounded in seams that
already exist but are currently **computed and thrown away**: `memory_refs`
(plumbed but always `[]`), `CodeImpactOverlay` (a deliberately-powerless
advisory edge), `Retrospective.build!/1` (computed once, written to disk at
`local_disk.ex:137`, never read back).

---

## 5. The First Light plan (pointer + map)

- **Plan doc:**
  `docs/2_implementation_plans/PHASE-2.5-FIRST-LIGHT-SYNCHRONOUS-LOOP-BEADS-INSIGHT.md`
  (committed). It is the execution of the serial pilot (P2-B7) that the
  9,022-line `PHASE-1.5-2-…-ULTIMATE-HYBRID.md` specified but left on stubbed
  pieces. **Step 1 revises it** per §6 + §10.
- **Sequencing philosophy (decided):** **product-first, gate-as-backstop.**
  Promote the eval bridge into production stations; reuse the 15-stage Gate +
  eval Scorecard as the honesty backstop; **defer** the heavyweight
  `qualification_gate` ceremony (emit its evidence, don't block on it). The
  ratified ADRs remain in force.

### The revised milestone ladder ("green first, then break it")

| #        | Milestone                       | What it proves / needs                                                                                                                                                                  |
| -------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **M0**   | Plan & contracts ✅ **DONE**     | Plan authored, `plan_audit` = **handoff_ready 100%**, scaffold + 14 red-on-base tests. **Add Falsifier Forge** (prove ACs red-on-base at lock, pre-agent) in Step 1.                    |
| **M1**   | One slice green (**next**)      | Promote eval bridge → production stations; drive **SLICE-001** to a gate-pass via **ReferenceSolution** (then Codex). The loop physically runs one slice end-to-end. **See §8.**        |
| **M2**   | Full happy path                 | All 7 slices to `:accepted` via `SerialDriver`; replay-stable across two cassette runs.                                                                                                |
| **M2.5** | **Back-Edge (NEW)**             | Wire `Conveyor.Genome.BackEdge` at gate-pass so the Genome accretes from run 1.                                                                                                        |
| **M3**   | Widen the live gate             | Light `contract_lock`, `diff_scope`, `secret_safety` with real contexts; happy path still green (non-vacuous). _(Eval terminal is already lighting gate stages — now 9/14; helps M3.)_ |
| **M4**   | Canary mutants                  | Per-slice `mutants.json` on Beads Insight's own ACs; `false_pass_rate == 0`.                                                                                                           |
| **M5**   | Manufactured rework             | One slice `reject → needs_rework → feedback → green`. **Requires AttemptLoop + Rework Synthesizer (§9).**                                                                               |
| **M6**   | (Optional) Interrogation        | Flip on the planted ambiguity (Appendix A §6 of the plan); Interrogator parks the slice.                                                                                               |
| **M7**   | **Sealed Verdict / moat (NEW)** | First `trust_bundle@1` / DSSE-wrapped gate verdict — the first artifact of the actual product.                                                                                         |

**The clean-signal rule (load-bearing):** only `loop_integrity` (a known-good
reference patch must PASS) and `false_pass_rate` **block CI**; agent-capability
metrics only _warn_. A red CI then always means "the factory is broken," never
"the task was hard." This is exactly why M1 uses ReferenceSolution first.

---

## 6. ⚠️ THE CRITICAL CORRECTION — the loop cannot terminate today

The ideation's code archaeology found that the synchronous loop **physically
cannot iterate to done**, which my original plan silently assumed it could:

- `RunSlice.Result.status` is only `:succeeded | :failed`. The real verdict
  lives on `run_attempt.outcome` after `Gate.Finalizer.finalize!` — and the
  terminal accepted outcome is `:accepted` (NOT `:done`).
- On a non-fatal gate fail, `Finalizer` sets the slice to `:needs_rework` and
  **dead-ends** — nothing re-enters.
- `create_retry_attempt!/3` **raises** unless status is `:failed` (lines 78-82),
  but the rework path leaves status `:needs_rework`. So a retry literally cannot
  be forged from a rework.
- There is **no multi-attempt conductor** and **no multi-slice driver**.

**Consequence:** M1 (one slice, first-try green) works without these (single
attempt, no rework). But M2 needs a `SerialDriver`, and M5 / any real-world
reliability needs **AttemptLoop + Rework Synthesizer** (§9). These are
**prerequisites folded into the critical path**, NOT backlog.

---

## 7. The forcing-function target: Beads Insight (DONE — M0)

A read-only Python CLI `br-insight` over `.beads/issues.jsonl`. **Hermetic by
construction** (no network, no live `br`, no wall-clock) so every AC is a hard
pass/fail and the Gate genuinely bites.

- **Plan artifact:** `samples/beads_insight/conveyor.plan.yml`
  (`conveyor.plan@1`: 8 requirements, 16 ACs each bound to a real pytest node, 7
  slices, decisions, non-goals). **Constitution:** `samples/beads_insight/plan.md`.
- **Base-repo scaffold (committed):** `samples/beads_insight/` — `pyproject.toml`,
  `src/br_insight/{model,loader,clock,report,cli}.py` + `commands/{ready,cycles,epics,velocity,digest}.py`,
  `tests/` (8 test modules with the 16 AC node-ids), `tests/fixtures/{issues,cyclic,malformed}.jsonl`,
  `tests/golden/digest_2026-06-19.md` (PENDING sentinel), `AGENTS.md`.
- **Locked interfaces (the only 2 cross-slice contracts; `model.py` ships in the
  seed fully defined — it IS the interface):** `Issue`/`IssueGraph` dataclasses;
  the `br_insight.report@1` JSON envelope. Everything else (loader, commands,
  report builder, clock) is a **stub raising `NotImplementedError`** — the
  implementer's real work.
- **Calibration state:** 16 tests collect; **14 are RED on base** (intended —
  the red-on-base calibration substrate), 2 pass vacuously (argparse
  bad-format + the no-wall-clock guard).
- **The 7-slice diamond:** SLICE-001 loader+model (root, all depend on it) →
  SLICE-002 `ready` / 003 `cycles` / 004 `epics` / 005 `velocity` (4 independent
  forks) → SLICE-006 `digest` (join) → SLICE-007 `--format json` + `report@1` +
  determinism sweep (terminal, L2). Compiler **derives** the fork/join from
  `conflict_domains` + `likely_files`; slices have no explicit dependency field.
- **Pinned fixture values (the implementer must satisfy):** 22 issues / 8 edges;
  epic E1 → total=5/closed=2/pct=40; E2 → total=0/pct=100; velocity
  `[3,1,0,2]` for `--as-of 2026-06-19T00:00:00Z`; cycle `A→B→C→A` canonical;
  malformed JSON on line 7.

**M0 verification result (decisive):** `mix conveyor.plan_audit
samples/beads_insight/conveyor.plan.yml` → **handoff_ready, 100% on clarity /
acceptance / testability / traceability / architecture / autonomy, 0 findings, 7
slices, 0 orphaned.** R2 (does a real plan lower?) is fully de-risked.

**Two known findings (cosmetic / non-blocking):** (1) `missing_hard_constraint`
— `plan_lint.ex:75` hard-flags a top-level `constraints` array that
`conveyor.plan@1`'s `additionalProperties:false` forbids; every plan including
the reference sample hits it; `plan_audit` is still `handoff_ready`. Cheap fix:
add `constraints` to the schema or downgrade the finding. (2) `tasks_service`
lock pins `pytest==9.1.0` which doesn't resolve in this env (latest 9.0.3); CI
has the pinned wheel.

---

## 8. THE NEXT BUILD — M1: promote the eval bridge to a production width-1 loop

### 8.0 M1 execution status (live — updated 2026-06-20)

**Grounding finding (important):** the eval Golden-Thread gate checks **all** of a
plan's `required_test_refs` as one `acceptance_locked` suite
(`ToolchainRunner.acceptance_test_refs/1`), so a gate-pass on the 7-slice plan via
the existing harness needs a COMPLETE reference solution. Per-slice gate scoping
(each slice's gate checks only its own ACs) is M1b productionization. So M1
splits:

- **M1a (✅ GREEN — 2026-06-20):** the WHOLE Beads Insight plan drove the full
  loop to a real gate-pass via the Golden-Thread harness + the complete
  reference solution (loop-integrity proof on the real plan, $0). Proven by
  `test/conveyor/eval/beads_insight_golden_thread_test.exs`.
- **Codex (✅ live build — 2026-06-20):** the live Codex adapter built the whole
  CLI from the stub workspace + an implementation brief; its diff passed real
  pytest (16 green) and the deterministic gate
  (`test/conveyor/eval/beads_insight_codex_live_test.exs`, `:live_agent`,
  ~10.7 min): `gate_passed: true`, `findings: []`. **The factory turned a real
  plan into gate-passing software via a real agent, synchronously** — and because
  the gate was proven to discriminate first (M4), the PASS is trustworthy.
  ✅ **Diff-scope verified (2026-06-20):** a re-run with a diff-scope assertion
  confirms Codex changed exactly **9 files, ALL under `src/br_insight/`**
  (`model.py`, `tests/`, the golden, the plan all untouched) — it implemented the
  code, it did not tamper; reproducible across 2 independent runs. The integrity
  claim is now bulletproof at the test level. (Wiring the `diff_scope` gate STAGE
  *inside the loop* is still the M3 hardening, but the claim no longer rests on it.)
- **M1b:** productionize into `Conveyor.Stations.*` + `RunSpecAssembler` +
  per-slice ContractLock/gate-scoping (§8.1–8.4), so a SINGLE slice runs against
  its own contract.

**✅ DONE — the M1 loop-integrity control:** the complete `br_insight` reference
solution is committed as
`samples/beads_insight/.conveyor/canary/reference_full.patch` (+ `mutants.json`
manifest + the regenerated `tests/golden/digest_2026-06-19.md`). It applies via
`patch -p3` and passes all 16 ACs in a fresh copy ($0, deterministic); the
committed base src stays RED. This is the known-good every run is verified
against.

**✅ M1a DONE (2026-06-20)** — implemented + GREEN in
`test/conveyor/eval/beads_insight_golden_thread_test.exs` (`run_status: :succeeded`,
`verification: "passed"`, `gate_passed: true`); the `tasks_service` regression
anchor stays green and the gate discriminates (known-good PASS, mutants FAIL).
**▶ NEXT:** (1) ✅ **M4 DONE (2026-06-20)** — 3 behavioral mutants
(`ready_includes_blocked`/AC-003, `cycles_missed`/AC-005, `epics_miscount`/AC-007);
the reference PASSES and all 3 mutants FAIL the gate (`false_pass_rate=0`) on the
real 7-slice plan via `beads_insight_golden_thread_test.exs`. The gate
discriminates on Beads Insight's own ACs. (2) **M1b productionize** — `Conveyor.Stations.*` + `RunSpecAssembler` + per-slice
ContractLock/gate-scoping (§8.1–8.4) so a SINGLE slice runs against its own
contract. (3) **M2** — `Conveyor.Planning.SerialDriver` over all 7 slices.
(4) loop-closers (AttemptLoop + Rework Synthesizer, §9). (5) swap `AgentStation`'s
adapter to `Codex` for the agent proof. Run cmd:
`MIX_ENV=test PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres mix test test/conveyor/eval/beads_insight_golden_thread_test.exs --include eval`.

_(historical M1a wiring note:)_ generalize `test/support/bridge_fixtures.ex` (today
hardcoded to `samples/tasks_service`) to accept a sample path + plan path +
`patch_ref`; build the Ash chain (Project→Plan→Epic→Slice→RunPrompt→RunSpec→
RunAttempt→AgentSession) + materialize the workspace for `samples/beads_insight`;
then call `Conveyor.Eval.GoldenThread.run_pipeline/1` with `patch_ref =
"samples/beads_insight/.conveyor/canary/reference_full.patch"`. Assert
`run_status == :succeeded` and `gate_passed`. Reference test:
`test/conveyor/eval/golden_thread_test.exs`. Needs the Postgres container (§13) +
a venv with pytest. Exact shapes (from the session's Explore map): `ReferenceSolution`
opts `:reference_patch` / `:agent_session_id` / `:blob_root`; `AgentStation` reads
`patch_ref` from station input and defaults to `ReferenceSolution`; gate stages
`[Conveyor.Gate.Stages.TestExecution]`; calibration `%{status: :valid,
expected_failures: ["acceptance_red_on_base"]}`. Patch strip level is `-p3`
(`a/samples/beads_insight/...`).

---

This is the immediate engineering work. **6 NEW modules + a few EDITs.** The
hard distributed-systems plumbing already exists; this is mostly writing
production station modules + a RunSpec assembler and registering them.

**M1 decision (this session): use the `ReferenceSolution` adapter FIRST** — a
known-good patch must drive the production stations to a gate-pass ($0,
deterministic, the `loop_integrity` control). This means **you must author a
known-good reference implementation of SLICE-001's loader** (the correct
`loader.py` that makes the loader/model ACs green) as the reference patch. Only
after the loop is proven green do you swap `adapter_module/1` to `Codex`.

### 8.1 NEW modules

1. **`Conveyor.Stations.Implementer`** (station key `"implement"`) — Codex-wired
   clone of `Conveyor.Eval.AgentStation`. `use Conveyor.Station, station:
   "implement"`; `effects/0 == [:file_write]`; loads `AgentSession` +
   `RunPrompt`; builds `workspace = %{path, base_commit}`; calls
   `AgentRunner.run(adapter, run_prompt, workspace, policy, opts)`; emits
   `agent_diff`. **Only deltas from `AgentStation`:** `adapter_module/1` is
   configurable (default `Codex`; pass `ReferenceSolution` for M1), and
   `policy()` loads the real `Policy` row.
2. **`Conveyor.Stations.Verify`** (key `"verify"`) — `Eval.VerifyStation`
   (honest evidence via `ToolchainRunner.verification_result/3`) **plus**
   persisting `Factory.Evidence` via `Conveyor.Evidence.Recorder.record!/5` (the
   un-stubbed `RecordEvidence`).
3. **`Conveyor.Stations.ContextScout`** (key `"context_scout"`) — thin wrapper
   over real `Conveyor.ContextScout.run!`, returns `ContextPack` id.
4. **`Conveyor.Stations.BaselineHealth`** + **`Conveyor.Stations.AcceptanceCalibration`**
   — thin wrappers over `Conveyor.BaselineHealth.run!/2` and
   `Conveyor.AcceptanceCalibration.run!/2`. Calibration output
   (`%{status: :valid, expected_failures: [...]}`) is exactly the
   `test_pack_calibration` the gate needs.
5. **`Conveyor.Planning.RunSpecAssembler`** (biggest new module) —
   productionizes the test-only `BridgeFixtures` chain (`test/support/bridge_fixtures.ex`):
   materialize the git workspace via real `Conveyor.Sandbox` (not the test's
   `rsync`+`git init`), compute `base_commit`, allocate `blob_root`, call the
   pure lowering, augment station inputs, write the immutable `RunSpec` row with
   `station_plan` + `station_plan_sha256`.
6. **`Conveyor.Planning.SerialDriver`** (needed at M2) — topo-orders
   `PilotSelection.freeze/1`'s `selected_slice_ids` from `work_graph`
   execution-hard edges; for each slice: `RunSpecAssembler` → `RunSlice.run!` →
   `RunGate.run_gate_only!` → record a `PilotExecution` event; halt/park on gate
   failure (width 1, no fleet).

### 8.2 EDITs

- `Conveyor.Eval.WorkGraphToStationPlan` → copy to
  `Conveyor.Planning.WorkGraphToStationPlan` (lowering is pure & permanent);
  extend station list from `["agent","verify"]` to
  `["context_scout","baseline_health","acceptance_calibration","implement","verify","record_evidence"]`.
- `config/*.exs` → populate `:station_modules` with the 6 keys (consumed by
  `RunSlice.station_module!/2`; today empty except a demo `FakeRunnerStation`).
- `Jobs.RunImplementer` / `RecordEvidence` → delete the `WorkerStub` no-op.

### 8.3 Un-stubbing the live loop (minimal for M1)

- **ContractLock + AgentBrief:** run `ContractForge.ContractAuthor.materialize/1`
  to mint the `AgentBrief` from the slice ACs; persist `AgentBrief` /
  `ContractLock` / `TestPack`; gate the slice on `Readiness.check/2 == :ready`
  before assembling the RunSpec; feed the real `contract_lock_sha256` /
  `policy_sha256` into the gate (replacing `sha256:bridge`).
- **Policy / claim_controls:** `Station.execute!` defaults claim controls to
  active when absent (so it runs today); production un-stub passes a real
  `:claim_controls` map from `Conveyor.Planning.Admission`.

### 8.4 Ordered M1 sequence

(a) station-modules registry + the 5 station wrappers → (b) production
`WorkGraphToStationPlan` list → (c) `RunSpecAssembler` → (d) un-stub
ContractLock/AgentBrief via `ContractAuthor` + `Readiness` → (e) author the
SLICE-001 reference patch + wire `ReferenceSolution` as the implementer adapter
→ (f) drive SLICE-001 end-to-end to gate-pass (`:accepted`). **Keep
`test/conveyor/eval/golden_thread_test.exs` green throughout** — it exercises the
identical fold and is the regression anchor.

**Environment for running it:** Postgres via OrbStack container (§13). The agent
station + sandbox need Docker (OrbStack is up). The project enforces **TDD** (the
`tdd` skill) — write the failing test for each new module first.

---

## 9. The bet trio — build right after M1 (closes the loop + seeds the moat)

Grounded specs (module names + seam gaps verified against the real code). Build
these immediately after SLICE-001 is green.

**A. `Conveyor.AttemptLoop.run_to_done!/2`** — the width-1 multi-attempt
conductor. Wraps `RunSlice.run!` + `Gate.Finalizer.finalize!`; branches on
`run_attempt.outcome` (`:accepted`/`:policy_blocked`/`:rejected` terminal;
`:needs_rework` retries); forges the next attempt up a recorded **escalation
ladder** (same effort → raise `codex_reasoning_effort` minimal|low|medium|high →
failing-test-pinned brief → halt-and-summarize) until terminal or a typed
attempt budget exhausts. **Required fixes:** relax `create_retry_attempt!/3` to
accept `:needs_rework` (not just `:failed`); add a `RunSpec` forge helper that
clones `station_plan` + bumps `attempt_no`; add an `AttemptBudget` (modeled on
`RunBudgetGuard`'s ledger pattern); emit an `attempt.escalated` event per rung.
_Files:_ `run_slice.ex`, `run_attempt_lifecycle.ex`, `gate/finalizer.ex`,
`policy/run_budget_guard.ex`, `retrospective.ex`, `factory/run_attempt.ex`.
**Moat:** a per-`(slice, attempt_no, rung, finding_category, outcome)` corpus —
the training set for learning the cheapest rung that resolves each finding-class.

**B. `Conveyor.Recovery.ReworkSynthesizer.synthesize/2`** — the literal missing
edge: compile the Gate's **typed** `findings` (string-keyed maps with
`category`/`severity`/`stage`/`message`; `acceptance_mapping` adds
`acceptance_criterion_id` + `evidence_status`) into an AgentBrief **delta**
(v_n+1) that names exactly which ACs failed and forbids regressing the green
ones. Persist as a new brief via the existing `unique_slice_version` identity;
add a `source(:prior_findings, :trusted, …)` to `PromptBuilder.build!/2` (it
already separates `:trusted` sources from the `@untrusted_banner`); after
`Finalizer` returns `:needs_rework`, call synthesize then
`SliceLifecycle.transition!(slice, :mark_ready)` (the `:needs_rework → :ready`
edge already exists). **Moat:** a labeled `(finding → delta → next-verdict)`
repair corpus no one else can synthesize.

**C. `Conveyor.Genome.BackEdge`** — at every gate-pass, mint immutable
`code_symbol → claim → AC → decision` provenance edges (promote the advisory
`CodeImpactOverlay` into its proven inverse). Reuse the `ArtifactInputIndex`
record shape with a new `verified_by_gate` role; consume the gate-passed
`GateContext` (`patch_set.patch_sha256`, `acceptance_criteria`) +
`Planning.Claims.claims_by_pointer` + `ContractLock`; persist
`conveyor.code_provenance_edge@1`; call from the gate-pass branch. **This is the
seed asset** the Genome (anti-corpus, genome-seeded context, readiness oracle)
compounds on — wire it at **M2.5** so it accretes from run 1.

Then the compounding payoff: **`Conveyor.Factory.FailureMemory` (the Scar
Ledger)** — distill landfilled `Retrospective.build!` output into content-
addressed "scars" keyed by `conflict_domain`, fill the always-empty `memory_refs`
slot, render a "## Known Pitfalls in THIS code" section in `PromptBuilder`; and
**`Genome-Seeded Context`** — seed slice N+1's prompt from proven neighbor edges
+ critic-rejected alternatives (the single most direct `pass@1` lever).

---

## 10. The full ideas catalog (clustered) — the enhancement roadmap

200 ideas were generated across two passes and adversarially judged. The second
pass (rubric: **moat × boldness × groundedness × advances-the-synchronous-
factory**, complexity NOT penalized) produced the bold, grounded set below. Full
deep write-ups (with line-level grounding) are in the workflow transcript files
under the session dir (see §15) while they persist; the essential specs are
captured here and in §9.

**Cluster 1 — Close the loop (build NOW; M1–M5 critical path):** AttemptLoop
(§9A) · Rework Synthesizer (§9B) · Falsifier Forge (execute the dormant
`FalsifierSeedDeriver` seeds red-on-base **before** the contract locks — moves
calibration upstream of token spend; M0+) · Convergence Sentinel (anti-thrash
governor for the repair loop) · Repeat-Offender Escalation (when a scar fires N
times, re-cut the plan via the real `PlanAmendments.propose/1`) · Cost-Aware
Retry Governor (each attempt must pay for itself).

**Cluster 2 — The Genome (the moat; wire during/after First Light):** The
Back-Edge (§9C) · The Scar Ledger / `FailureMemory` (§9) · Genome-Seeded Context
(§9) · Readiness Oracle + Decomposition Tournament (corpus-fit, Brier-calibrated
predictors of `P(gate-pass)` keyed to contract/slice-cut digests) · Regression
Cassette (every green run becomes a permanent $0 contract test — needs the
cassette to also record the verdict + `evaluation_surface_digest`).

**Cluster 3 — Verifier as a product (next phase, after the loop):** The Sealed
Verdict (DSSE-wrap the Gate's own reproducible verdict, not just the diff — the
M7 moat artifact) · Findings-to-Fix (external FAIL → contract → width-1 run
satisfies it — verifier as demand funnel for the generator) · Vacuity-as-a-
Service (point `IntegritySentinel` at a foreign PR's own tests → a portable
"these tests don't test anything" verdict) · Provenance Linker (unbroken
plan→patch→verdict lineage; also closes a real tamper gap) · Offline Trust
Verifier (`conveyor verify-bundle`, zero runtime) · Negative Provenance (sign
the rejections — effort S) · Contract Inference (reverse-compile a brief from a
PR + its tests).

**Cluster 4 — Debugging god-mode:** Divergence Bisector (git-bisect for the
event log; `ReplayDiagnostics.compare` is already a first-divergence finder;
kills the #1 width-1 time sink).

**The bets (committed roadmap):** AttemptLoop + Rework Synthesizer + Falsifier
Forge (make the loop terminate) + Back-Edge (seed the Genome from run 1). Then
Genome-Seeded Context + Scar Ledger (the compounding payoff). The verifier-as-
product cluster is the next phase, led by The Sealed Verdict.

**The earlier "timid 10"** (in the plan doc's §10 today) were hygiene dressed as
bold and are superseded by the above — Step 1 replaces them. (A few survive as
real near-term wins: self-report↔evidence reconciliation, `mix conveyor.run`,
Needs-a-Human inbox, crash-safe station commit.)

---

## 11. Sequencing reasoning (why this order)

The risk at this point is **strategy-astronaut paralysis** — the strategy got so
good it became its own trap, while the factory still hasn't turned one plan into
working software. The cure is to **build the loop**, with just enough planning to
build the right thing. Order: (1) fast lean plan-fix so we don't build against a
known-broken map; (2) **build M1** — you cannot iterate a loop that can't run
once, so the production stations (§8) come BEFORE the iteration layer (§9); (3)
the bet trio; defer further idea-mining indefinitely (we have more than enough).

---

## 12. Decisions made this session (authoritative)

- **Target:** Beads Insight CLI (read-only Python, hermetic, injected `--as-of`
  clock). The CLI is the proof artifact; **Conveyor is what's under test.**
- **Sequencing:** product-first, gate-as-backstop; defer the qualification
  ceremony (emit evidence, don't block).
- **Validation:** "green first, then break it" (M0→M3 green, then M4 canaries +
  M5 rework).
- **M1 agent:** **ReferenceSolution first** (prove loop wiring, $0,
  deterministic), **then Codex** (prove the agent). Requires authoring a
  known-good SLICE-001 reference patch.
- **Parallelism:** deferred (Law 27, width 1).
- **Commits:** **at each checkpoint** on branch
  `feat/first-light-m0-beads-insight` (off `main`, shared with the eval
  terminal). Use explicit pathspecs; do not sweep unrelated changes.
- **The loop-can't-terminate finding (§6) is folded into the critical path** —
  AttemptLoop + Rework Synthesizer are prerequisites, not backlog.

---

## 13. How to run things (environment)

- **Postgres (DB-backed mix tasks):** OrbStack `postgres:16` container named
  `conveyor-pg` on host **:5433** (isolated from local PG on 5432). Dev config
  reads `PG*` env. Recipe:
  ```bash
  docker run -d --name conveyor-pg -e POSTGRES_USER=postgres \
    -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=conveyor_dev -p 5433:5432 postgres:16
  # wait for ready, then:
  PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGHOST=localhost PGDATABASE=conveyor_dev \
    mix ecto.create && mix ecto.migrate
  ```
  Prefix DB-backed tasks with the same `PG*` env. Tear down: `docker rm -f conveyor-pg`.
- **Pure (no DB) compiler checks:** `mix conveyor.plan_lint PLAN.md`,
  `mix conveyor.plan_prepare PLAN.md --no-agents`.
- **Full audit (DB):** `mix conveyor.plan_audit PLAN.md`.
- **Existing operator tasks:** `mix conveyor.run_slice`, `mix conveyor.demo`,
  `mix conveyor.verify`, `mix conveyor.doctor`, `mix conveyor.gate_canary`,
  `mix conveyor.compiler_structure_gate --input …`, the eval suite
  (`mix conveyor.eval.{rung0,replay,lift,scorecard}`).
- **Plan format:** `conveyor.plan@1` (YAML or JSON; `YamlElixir`). Keys:
  `REQ-NNN`/`AC-NNN`/`DEC-NNN` (`^[A-Z]+-[0-9]{3}$`), `SLICE-NNN`. Slices have
  no dependency field — the compiler derives the graph from `conflict_domains` +
  `likely_files`. Template: `samples/tasks_service/conveyor.plan.yml`.

---

## 14. Conventions (enforced)

- **`br` (beads_rust), never `bd`**, for work tracking (`.beads/`). Resolve
  `ACTOR="${BR_ACTOR:-assistant}"` for mutations; `br dep cycles --json` must be
  empty; `br sync --flush-only` (never commits git).
- **TDD** via the `tdd` skill (root `AGENTS.md`). Write the failing test first.
- Ash resources in `lib/conveyor/factory/`, one file each, registered in
  `lib/conveyor/factory.ex`; paired `priv/repo/migrations/` updates (append-only).
- Pure compiler passes (`lib/conveyor/planning/`) — no side effects; memoize
  only with all inputs declared. Oban workers are orchestration edges, not
  business logic. Stations use the `Conveyor.Station` behaviour.
- `@N` versioned schemas: `docs/schemas/conveyor.<name>@N.json`, append-only
  within a major; new required field / changed enum ⇒ new major. Canonical JSON
  = `rfc8785-jcs`; digests via `CanonicalJson.digest/1`.
- Tooling gate: `mix format --check-formatted`, `mix credo --strict`,
  `mix dialyzer`. Commit messages: conventional-commits; end with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Never** weaken tests/contracts/policy/evidence to pass a gate; never let the
  code-writer author its own contract/red-team; never bypass policy
  normalization; never edit `priv/conveyor/templates/` as ordinary code.

---

## 15. Risks & open questions

- **R1 (highest):** the generator seam actually closes for a real plan. _Mit:_
  M1 proves one slice end-to-end first; golden-thread test stays green as the
  anchor; ReferenceSolution isolates loop from agent.
- **R3:** the gate stays byte-identical & authoritative as stages go live. _Mit:_
  M3 lights stages one at a time and asserts the happy path still PASSES. (Eval
  terminal is concurrently wiring GateContext stages — now 9/14 — coordinate.)
- **R4:** pytest determinism in a real repo. _Mit:_ injected `--as-of` clock,
  determinism-sweep AC, replay-stability at M2.
- **Codex auth** must be set up before the "then Codex" half of M1 (the
  ReferenceSolution half does not need it).
- **Shared branch:** the eval terminal commits to `feat/first-light-m0-beads-insight`
  too. Commit with explicit pathspecs; `git pull`/check before each commit.

---

## 16. File & pointer index

- **This handoff:** `docs/2_implementation_plans/00-FIRST-LIGHT-HANDOFF.md`
- **First Light plan (revise in Step 1):**
  `docs/2_implementation_plans/PHASE-2.5-FIRST-LIGHT-SYNCHRONOUS-LOOP-BEADS-INSIGHT.md`
- **The big upstream program:**
  `docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md`
- **Strategy / decisions:** `docs/BRAINSTORM.md`; ADRs in `docs/adrs/` (override
  BRAINSTORM).
- **Eval program (parallel work, another terminal):**
  `docs/3_evals/CONVEYOR-EVAL-PROGRAM-AND-REALITY-MAP.md`,
  `docs/3_evals/IMPLEMENTATION-PLAN-RUNGS-0-1.md`.
- **Codebase docs (authoritative "what's built"):** `droid-wiki/` (start at
  `overview/architecture.md`, `systems/index.md`, `primitives/index.md`,
  `background/design-decisions.md`).
- **Forcing-function target:** `samples/beads_insight/` (plan + scaffold).
- **Reference plan template:** `samples/tasks_service/conveyor.plan.yml`.
- **Schemas:** `docs/schemas/` (`conveyor.plan@1.json`, `conveyor.work_graph@2.json`, …).
- **Auto-memory (persists across sessions):**
  `~/.claude/projects/-Users-robertguss-Projects-startups-software-factory-ai/memory/`
  (`first-light-sync-loop-plan.md`, `conveyor-eval-program-and-reality.md`,
  `conveyor-planning-collaboration.md`).
- **Idea workflow transcripts (deep write-ups, while they persist):** session
  `tasks/` dir — `wb9xqmhds.output` (first 100-idea pass, the "timid 10"),
  `wl2gajlte.output` (second 100-idea pass, the bold/moat set + 28-row
  scoreboard).
