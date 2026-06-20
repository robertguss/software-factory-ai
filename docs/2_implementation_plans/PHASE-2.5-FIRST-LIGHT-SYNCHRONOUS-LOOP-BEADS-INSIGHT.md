# Phase 2.5 — "First Light": the synchronous loop, end-to-end, on a real plan

> **Status:** implementation plan, course-corrected on 2026-06-20. Pending an
> ADR to ratify the phase number and the "product-first, gate-as-backstop"
> sequencing choice (see §11). ADRs override this doc where they conflict.
>
> **One-line outcome:** Conveyor takes one real human plan and drives it — width
> 1, no fleet — through the full production loop (ingest → compile → forge
> contracts → Codex-in-sandbox → independent evidence → 15-stage Gate → reviewer
> → branch) to a merged, gate-passing result, and we prove the loop is **honest
> at its failure boundaries**, not just green on the happy path.
>
> **The thing under test is Conveyor, not the CLI.** The CLI ("Beads Insight")
> is the forcing function and the proof artifact. Definition of done is measured
> on the factory's behavior.

---

## ⚠️ Course-correction (2026-06-20) — read before the rest

Two things changed after a deeper ideation pass. Full detail + the bold ideas
catalog live in **`00-FIRST-LIGHT-HANDOFF.md`** (read it first); this is the
delta.

**1. The loop cannot terminate today (critical).** Code archaeology found the
synchronous loop physically can't iterate: `RunSlice.Result.status` is only
`:succeeded|:failed`; the real verdict is `run_attempt.outcome` (terminal accept
is `:accepted`, not `:done`); `Gate.Finalizer` dead-ends at `:needs_rework`; and
`create_retry_attempt!/3` raises unless status is `:failed`. So the
**loop-closers are prerequisites, not backlog.** Milestone deltas:

- **M0** gains **Falsifier Forge** — execute the dormant `FalsifierSeedDeriver`
  seeds red-on-base _at contract lock_ (pre-agent), so bad ACs die before spend.
- **M1** runs **ReferenceSolution-first** (prove loop wiring, $0) then Codex.
- **M2** needs `Conveyor.Planning.SerialDriver` (multi-slice, width 1).
- **NEW M2.5 — Back-Edge:** wire `Conveyor.Genome.BackEdge` at gate-pass so the
  Genome accretes from run 1.
- **M5** requires `Conveyor.AttemptLoop` + `Conveyor.Recovery.ReworkSynthesizer`
  (specs in handoff §9) — without them the loop can't rework to green.
- **NEW M7 — Sealed Verdict:** first DSSE-wrapped gate verdict /
  `trust_bundle@1` — the first artifact of the actual product.

**2. The strategy: verifier-as-product + the Genome.** Conveyor's defensible
product is the trust layer for AI-written code; its moat is **the Genome** — a
content-addressed, gate-verified `intent ↔ code ↔ verdict ↔ outcome` graph that
accretes every run. The loop generates the Genome; the Genome makes the loop
succeed more. The "timid 10" in §10 are **superseded** by the clustered bold
catalog in handoff §10 (Close-the-loop / Genome / Verifier-as-product /
Debugging) and the bet trio (AttemptLoop + Rework Synthesizer + Falsifier
Forge + Back-Edge).

---

## 0. Where this sits

This plan is the **execution** of the serial pilot that the
`PHASE-1.5-2-…-ULTIMATE-HYBRID` program specified (P2-B7) but left running on
_stubbed_ live-loop pieces. The eval program (Rungs 0–2 + R5 Lift Duel) has, as
a side effect, already built the missing bridge — `Golden Thread` (work-graph →
station-plan + agent station), the real `Codex` adapter, and the cassette
flywheel. **First Light promotes that eval bridge into the production
synchronous loop and points it at a real plan.**

It is deliberately _product-first_: it does **not** require the full heavyweight
Trust-Qualification ceremony (Evidence Kernel hardening + `qualification_gate` +
scoped grants) to run first. Instead it reuses the parts already built and uses
the **15-stage Gate + eval Scorecard as the honesty backstop**, emitting
qualification evidence as a by-product so the formal grant can be issued later
without rework. The ratified ADRs (determinism boundary, actor separation,
contract-evolution-mints-a-new-lock, projections-are-not- authority) remain in
force unchanged.

Parallelism (Dispatcher / WorkerPool / MergeQueue / Governor) stays
**deferred**, consistent with Law 27 (implementation width = 1; merge manual).
See §11.

---

## 1. The precise gap this closes

The current reality, in one sentence: **"Conveyor can rigorously _judge_
software it cannot yet _build_."** The verifier is real and runs for \$0; the
_generator_ seam is severed in production.

What is **already real and reused unchanged**:

- `Conveyor.RunSlice.run!/2` and `Conveyor.Station.execute!/4` — the synchronous
  station-fold + wrapper (leases, idempotency, declared effects, artifacts,
  ledger, authority events). These are **not** eval code; the eval path uses
  them verbatim.
- `Conveyor.Jobs.RunGate` `run_gate_only!/3` — the 15-stage Gate facade.
- The Ash domain (~50 resources), the `Slice` + `RunAttempt` state machines, the
  pure planning compiler, `ContractForge`, `Readiness`, real Docker `Sandbox`,
  the `Codex` adapter, and the cassette engine.

What is **severed / stubbed** (the work of this plan):

- The only end-to-end "run a slice through stations" path that exists is the
  **eval** Golden-Thread one. Production "stations" (`Jobs.RunImplementer`,
  `Jobs.RecordEvidence`) are `WorkerStub` no-ops; `Jobs.ContextScout` /
  `BaselineHealth` / `AcceptanceCalibration` are Oban shells that delegate to
  real modules but **are not wired as stations in the fold**.
- `ContractLock` / `RoleView` / policy / `ContextPack` are **stubbed in the live
  loop** (the eval path fakes them with `sha256:bridge` digests).
- The real agent (`Codex`) is wired only into the **eval** `AgentStation`.
- There is no running conductor/dispatcher/merge-queue — **fine**: width-1 sync
  needs only `RunSlice` + a thin serial driver over `PilotSelection`.

So promotion is **mostly: write production station modules + a production
RunSpec assembler, then register them in the station registry.** The hard
distributed-systems plumbing already exists.

---

## 2. The build — promote the eval bridge to a production width-1 loop

Grounded in the actual code. **6 NEW modules + a handful of EDITs.**

### 2.1 NEW modules

1. **`Conveyor.Stations.Implementer`** (station key `"implement"`) — a
   Codex-wired clone of `Conveyor.Eval.AgentStation`.
   `use Conveyor.Station, station: "implement"`; declares
   `effects/0 == [:file_write]`; loads the `AgentSession` + `RunPrompt`; builds
   `workspace = %{path, base_commit}`; calls
   `AgentRunner.run(adapter, run_prompt, workspace, policy, opts)`; emits the
   `agent_diff` artifact. **Only deltas from `AgentStation`:**
   `adapter_module/1` defaults to `Conveyor.AgentRunner.Codex` (not
   `ReferenceSolution`), and `policy()` loads the real `Policy` row.
2. **`Conveyor.Stations.Verify`** (key `"verify"`) —
   `Conveyor.Eval.VerifyStation` (which already produces honest evidence via
   `ToolchainRunner.verification_result/3`) **plus** persisting
   `Factory.Evidence` through `Conveyor.Evidence.Recorder.record!/5`. This is
   the un-stubbed `RecordEvidence`. (Keep as one station or split `verify` →
   `record_evidence`.)
3. **`Conveyor.Stations.ContextScout`** (key `"context_scout"`) — thin
   `Conveyor.Station` wrapper over the existing real
   `Conveyor.ContextScout.run!`, returning the `ContextPack` id in its output.
4. **`Conveyor.Stations.BaselineHealth`** +
   **`Conveyor.Stations.AcceptanceCalibration`** — thin wrappers over
   `Conveyor.BaselineHealth.run!/2` and `Conveyor.AcceptanceCalibration.run!/2`.
   Calibration output (`%{status: :valid, expected_failures: [...]}`) is exactly
   the `test_pack_calibration` the gate needs — so **the gate reads real
   calibration** instead of the eval literal.
5. **`Conveyor.Planning.RunSpecAssembler`** (the single biggest new module) —
   productionizes the test-only `BridgeFixtures` chain: materializes the git
   workspace via real `Conveyor.Sandbox` (replacing the test's
   `rsync`+`git init`), computes `base_commit`, allocates `blob_root`, calls the
   pure lowering, augments station inputs, and writes the immutable `RunSpec`
   row with `station_plan` + `station_plan_sha256`.
6. **`Conveyor.Planning.SerialDriver`** — the width-1 multi-slice driver.
   `PilotSelection.freeze/1` already yields an ordered `selected_slice_ids`;
   `PilotExecution.summarize/1` only _summarizes_. The driver topo-orders the
   selection from `work_graph` execution-hard edges and, for each slice:
   `RunSpecAssembler` → `RunSlice.run!` → `RunGate.run_gate_only!` → record a
   `PilotExecution` event. Halts/parks on gate failure (width 1, no fleet).

### 2.2 EDITs

- `Conveyor.Eval.WorkGraphToStationPlan` → copy to
  `Conveyor.Planning.WorkGraphToStationPlan` (the lowering is pure & permanent);
  extend the station list from `["agent","verify"]` to the production sequence:
  `["context_scout","baseline_health","acceptance_calibration","implement","verify","record_evidence"]`.
- `config/*.exs` → populate `:station_modules` with the 6 new keys (consumed by
  `RunSlice.station_module!/2`). Today this registry is empty except a demo
  `FakeRunnerStation`.
- `Jobs.RunImplementer` / `RecordEvidence` → delete the `WorkerStub` no-op (work
  now lives in stations) or have them enqueue `Jobs.RunSlice`.

### 2.3 Un-stubbing the live loop (minimal)

- **ContractLock + AgentBrief:** run
  `ContractForge.ContractAuthor.materialize/1` to mint the `AgentBrief` from the
  slice's acceptance criteria; persist `AgentBrief` / `ContractLock` /
  `TestPack`; gate the slice on `Readiness.check/2 == :ready` **before**
  assembling the RunSpec; feed the real `contract_lock_sha256` / `policy_sha256`
  into the gate (replacing `sha256:bridge`). This makes the `contract_lock` gate
  stage real.
- **RoleView / TestPack:** a crude RoleView from the slice's bounded context is
  acceptable for width-1; full RoleView compilation stays deferred.
- **Policy / claim_controls:** `Station.execute!` defaults claim controls to
  active when absent (so it runs today); the production un-stub passes a real
  `:claim_controls` map (admission permit, grant, budget reservation) from
  `Conveyor.Planning.Admission` so emergency-stop / budget actually bind.
- **ContextPack:** replaced by the real `Stations.ContextScout`.

### 2.4 Ordered implementation sequence (engineering)

(a) station-modules registry + the 5 station wrappers → (b)
`WorkGraphToStationPlan` production list → (c) `RunSpecAssembler` (the
fixture→production lift) → (d) un-stub ContractLock/AgentBrief via
`ContractAuthor` + `Readiness` → (e) Codex as implementer default → (f)
`SerialDriver` over `PilotSelection` → (g) feed real calibration into the gate.
**Keep `golden_thread_test.exs` green throughout** — it exercises the identical
fold and is the regression anchor.

> **Idea #4 ("`mix conveyor.run`") is the natural CLI capstone of this
> section:** one operator command — `mix conveyor.run PLAN.md [--adapter codex]`
> — that drives a real plan through the production loop to a printed verdict + a
> `.conveyor/runs/<id>/` evidence path, with a stable `CLI.ExitCodes` exit. It
> becomes the canonical demo, the CI smoke test, and the "is the loop working?"
> check. Build it as the front door to the `SerialDriver`.

---

## 3. The forcing-function target — Beads Insight v1

A read-only Python CLI, `br-insight`, over `.beads/issues.jsonl`. **Hermetic by
construction** (no network, no live `br`, no wall-clock) so every acceptance
criterion is a hard pass/fail and the Gate genuinely bites. Full plan artifact
(the `conveyor.plan@1` Conveyor ingests) is in **Appendix A**.

Why it is a strong _system_ validator:

- **Crisp, machine-checkable ACs** (cycle `A→B→C→A` reported exactly;
  `digest --as-of` byte-stable) → the Contract Forge + Gate `acceptance_mapping`
  / `test_execution` stages have something real to check.
- **A real fork/join work graph** (1 root loader → 4 independent command forks →
  1 digest join → 1 terminal format/determinism slice) → exercises graph
  lowering, interface locks, and `diff_scope` / `workspace_integrity` on
  non-trivial topology, even at width 1.
- **Exactly two locked cross-slice interfaces** (`Issue`/`IssueGraph` model and
  the `br_insight.report@1` output schema) → ContractLock has precisely two
  interface surfaces to freeze.
- **The injected `--as-of` clock** teaches the agent Conveyor's own "no
  wall-clock" determinism rule and makes the gate verdict reproducible.

Honest limits (deliberate for v1): a **single archetype** (greenfield
pure-logic); a fully-specified plan won't fire the Interrogator unless we plant
an ambiguity (we do — Appendix A §6, off for the first green run); easy slices
won't fire rework unless we manufacture it (we do — §5).

---

## 4. Milestone ladder — "green first, then break it"

**Ordering principle: never inject a failure into a path you haven't first
observed go green** — a red result on an unproven path is uninterpretable. Each
milestone's exit criterion is a Scorecard with **zero blocking metrics**.

| #        | Milestone                      | De-risks | Exit criterion                                                                                                                                                                                                                      |
| -------- | ------------------------------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **M0**   | Plan & contracts               | R2       | `samples/beads_insight/conveyor.plan.yml` authored; pure compiler decomposes into the 7-slice diamond; `ContractLock`+`AgentBrief`+a **red-on-base** acceptance test forged per slice. Falsifier Forge runs before any agent spend. |
| **M1**   | One slice, green               | R1       | Promote the production station path into the synchronous `RunSlice` loop for **SLICE-001**. Drive it ReferenceSolution-first, then Codex, through real per-slice evidence and Gate finalization to `:accepted`. Scorecard green.    |
| **M2**   | Full happy path                | R2, R4   | `Conveyor.Planning.SerialDriver` runs every Beads Insight slice synchronously, width 1, to `:accepted`; acceptance tests green; **replay-stable** across two cassette runs.                                                         |
| **M2.5** | Back-Edge                      | —        | `Conveyor.Genome.BackEdge` mints gate-verified `code_symbol → claim → AC → decision` provenance edges on every gate pass, so the Genome accretes from run 1.                                                                        |
| **M3**   | Widen the live gate            | R3       | Light up `contract_lock`, `diff_scope`, `secret_safety` with **real** contexts (real `contract_lock_sha256`, not `sha256:bridge`). Happy path still green, proving the added stages are **non-vacuous**.                            |
| **M4**   | Canary mutants                 | —        | Per-slice `mutants.json` targeting Beads Insight's **own** ACs; `false_pass_rate == 0` across every slice (§5).                                                                                                                     |
| **M5**   | Manufactured rework            | —        | `Conveyor.AttemptLoop` + `Conveyor.Recovery.ReworkSynthesizer` drive one slice `reject → needs_rework → feedback → green`; the failing-AC category flows into the new brief (§5).                                                   |
| **M6**   | (Optional) Interrogation       | —        | Flip on the one planted ambiguity (Appendix A §6); Interrogator raises exactly one blocking question and the slice **parks** rather than guessing.                                                                                  |
| **M7**   | Sealed Verdict / first product | —        | Emit the first DSSE-wrapped Gate verdict / `trust_bundle@1`, wrapping the reproducible verdict rather than merely the diff.                                                                                                         |

M3 precedes breakage on purpose: "false-PASS = 0" only means something if the
gate stages are real; otherwise it is just "0 stages ran."

---

## 5. Gate-honesty validation (the heart of "validate the system")

**Reuse the machinery, not the corpus.** Today `MutantGauntlet` and
`RunGateCanary` read `samples/tasks_service/.conveyor/canary/mutants.json`.
Generate a **per-slice** `mutants.json` whose mutants violate Beads Insight's
own locked ACs (e.g. "ready-set excludes blocked issues" → a patch that includes
them), each tagged `expected_catch.stage = "test_execution"` and a `category`
naming the AC.

Run two complementary harnesses per slice:

- **`MutantGauntlet.run/1`** → emits `false_pass_rate` (already
  `blocking: true`). **Assertion: `0.0` for every slice.**
- **`RunGateCanary.run!/1`** with the wider M3 stage list → its `case_summary`
  distinguishes `false_negative` (mutant passed — the cardinal sin),
  `rejected_expected` (caught by the **right** stage/category), and
  `rejected_unexpected` (caught for the **wrong** reason). `ci_exit_code/1`
  fails CI on either a false-negative _or_ a right-answer-wrong-reason. This
  asserts **attribution**, not just catch.

**Manufactured rework cycle (M5):** build a slice whose first attempt uses the
naive "vanilla"-style brief that reliably leaves one AC red. Drive the real
`Slice` machine through `Conveyor.AttemptLoop`: `mark_ready` → `start` → `gate`
(FAIL → `:gated`) → `request_rework` (`:gated → :needs_rework`) →
`Conveyor.Recovery.ReworkSynthesizer` mints feedback from the gate `findings` →
**contract evolution mints a new lock/spec/attempt** (ADR) → `mark_ready`
(`:needs_rework → :ready`, the recovery edge) → `start` → `gate` (PASS) →
`integrate` → accepted. The load-bearing edges are `request_rework from: :gated`
and `mark_ready from: :needs_rework` — together they **are** the recovery loop.
Metric `rework_recovered@1` asserts the slice reached `:accepted` **and** the
feedback category matched the real gate finding (no fake recovery).

---

## 6. Keeping "loop broken" vs "task hard" clean (the signal rule)

A red gate could mean the conductor is broken **or** Codex couldn't solve the
slice. Disambiguate:

- **Reference-solution control.** Run each slice with a known-correct reference
  patch (like Lift Duel's reverse arm). A known-good diff **must** PASS — if it
  fails, the **loop/gate is broken**. If only the Codex arm fails, the **task is
  hard**.
- **Cassette pinning** holds agent behavior constant, so a verdict change across
  runs is a _loop_ change, never agent variance.
- **Held-constant confounds:** pin `reasoning_effort` so capability doesn't
  drift between green and break phases.

> **The clean-signal rule (load-bearing):** **only `loop_integrity` (reference
> passes) and `false_pass_rate` block CI; agent-capability metrics
> (`agent_pass_at_1`) only _warn_.** A red CI therefore always means "the
> factory is broken," never "the task was hard." This is the entire point of
> driving a real plan through the real loop.

---

## 7. Definition of done — measured on Conveyor

Every suite writes `conveyor.eval_metric@1` to `eval/scorecards/inputs/`;
`Scorecard.build/2` content-addresses them; `--gate` fails closed on any
blocking metric. First Light is **done** when, on the Beads Insight plan:

1. **`happy_path_complete`** (blocking) — all 7 slices reached `:accepted` via
   the real production loop (M2), with the widened live gate (M3).
2. **`loop_integrity`** (blocking) — every slice's reference-solution patch
   PASSES the gate.
3. **`false_pass_rate`** (blocking) — `0.0` across every slice's canary set
   (M4).
4. **`canary_false_negative`** (blocking) — `0` from `RunGateCanary` (M4).
5. **`rework_recovered`** (blocking) — the manufactured cycle recovered with
   matching feedback (M5).
6. **`replay_fidelity`** (blocking) — the run cassettes replay byte-identically.
7. _(Optional, M6)_ **`interrogator_fired`** — the planted ambiguity parked the
   slice.

The merged `br-insight` CLI is the **proof artifact**; these metrics are the
**verdict**. We additionally **emit** (not gate on) the qualification-evidence a
future `qualification_gate` would consume, so the formal scoped grant can be
issued later without rework.

---

## 8. Risks & mitigations (ranked)

- **R1 — the generator seam actually closes for a real plan (highest).**
  Mitigation: M1 proves a single slice end-to-end before anything else; keep the
  Golden-Thread test green as the anchor; reuse the exact fold the eval path
  already exercises.
- **R2 — a real plan decomposes into gradeable slices with red-on-base ACs.**
  Mitigation: M0 forges and _calibrates_ every contract (acceptance test red on
  the bare base) before any agent runs; if the compiler can't lower the plan,
  that surfaces at M0 with no wasted agent spend.
- **R3 — the gate stays byte-identical & authoritative as stages go live.**
  Mitigation: M3 lights stages one at a time with real contexts and asserts the
  happy path still PASSES (non-vacuous); the per-stage discrimination ledger in
  §10 catches a stage that never fires.
- **R4 — pytest determinism in a real repo.** Mitigation: injected `--as-of`
  clock (REQ-008), determinism sweep AC (no `datetime.now`), replay-stability
  exit at M2.
- **R5 — cost/usage stays meaningful.** Mitigation: `cost_per_verified_ac`
  counts ACs only through an _accepted_ gate; cassettes amortize real spend.

---

## 9. What we are explicitly NOT doing

Fleet / Dispatcher / WorkerPool / MergeQueue / Governor (Phase 3+). Auto-merge.
The full Evidence-Kernel hardening + `qualification_gate` ceremony (we emit its
evidence, defer its issuance). Multi-archetype coverage (v1 is one archetype).
Brownfield onboarding. Anything that assumes width > 1.

---

## 10. Enhancement backlog

This replaces the earlier "top 10" table with the bold, grounded catalog from
`00-FIRST-LIGHT-HANDOFF.md` §10. The priority is not more ideation; it is
closing the synchronous loop, then letting the loop generate compounding trust
data.

### Cluster 1 — Close the loop (build now; M1-M5 critical path)

- **AttemptLoop** — `Conveyor.AttemptLoop.run_to_done!/2` wraps `RunSlice.run!`
  and gate finalization, branches on `run_attempt.outcome`, retries
  `:needs_rework` attempts through an escalation ladder, and halts on terminal
  outcomes or attempt budget exhaustion.
- **Rework Synthesizer** — `Conveyor.Recovery.ReworkSynthesizer.synthesize/2`
  turns typed Gate findings into a trusted AgentBrief delta that names failed
  ACs and forbids regressing green ones.
- **Falsifier Forge** — execute dormant `FalsifierSeedDeriver` seeds red-on-base
  before contracts lock, so bad ACs fail before token spend.
- **Convergence Sentinel / Repeat-Offender Escalation / Cost-Aware Retry
  Governor** — keep repair from thrashing, re-cut plans when scars repeat, and
  make every retry justify its cost.

### Cluster 2 — The Genome (wire during/after First Light)

- **Back-Edge** — `Conveyor.Genome.BackEdge` mints gate-verified
  `code_symbol → claim → AC → decision` provenance edges on every pass.
- **Scar Ledger / FailureMemory** — distill `Retrospective.build!/1` output into
  content-addressed scars keyed by conflict domain; fill `memory_refs` instead
  of leaving it empty.
- **Genome-Seeded Context** — seed future prompts from proven neighbor edges and
  critic-rejected alternatives.
- **Readiness Oracle / Decomposition Tournament / Regression Cassette** — learn
  corpus-fit and gate-pass probability, and turn every green run into a
  permanent replayable contract test.

### Cluster 3 — Verifier as product

- **Sealed Verdict** — DSSE-wrap the Gate's reproducible verdict as
  `trust_bundle@1`.
- **Findings-to-Fix** — external verifier FAIL becomes a contract, then a
  width-1 run satisfies it.
- **Vacuity-as-a-Service / Provenance Linker / Offline Trust Verifier / Negative
  Provenance / Contract Inference** — make the verifier portable, inspectable,
  and useful outside Conveyor's generator loop.

### Cluster 4 — Debugging god-mode

- **Divergence Bisector** — use the event log and `ReplayDiagnostics.compare` to
  locate first divergence, cutting the main width-1 debugging time sink.

Near-term survivors from the historical table: self-report↔evidence
reconciliation, `mix conveyor.run`, Needs-a-Human inbox, crash-safe station
commit, Attempt Diff Lens, Scorecard regression guard, Per-Stage Discrimination
Ledger, and AGENTS.md drift checks in `conveyor.doctor`.

---

## 11. Parallelism — deferred, and why

We defer the fleet until the width-1 loop is proven. This is not just
pragmatism; it is the **ratified design** (Law 27: implementation width = 1,
merge manual; the ULTIMATE-HYBRID plan explicitly rejects "go straight to the
fleet" as "scales an unqualified loop — best demo path, wrong trust path"). The
entire fleet is parked at Phase 3+ in the beads backlog.

Two structural reasons First Light _earns_ later parallelism rather than
blocking it: (1) the **locked interfaces** (Beads Insight's `IssueGraph` +
`report@1`) are exactly the contracts that let dependent slices be built against
stubs in parallel later; (2) the Lift Duel scorer/evidence schema already "must
not assume width 1," so the measurement seam is forward-compatible. We turn the
dial up only once `false_pass_rate`, `loop_integrity`, and `rework_recovered`
are durably green — autonomy earned by a measured gate, not asserted.

---

## Appendix A — Beads Insight v1 plan artifact (`conveyor.plan@1`-shaped)

To be materialized as `samples/beads_insight/conveyor.plan.yml` at M0.

**Intent.** A read-only `br-insight` CLI that reads `.beads/issues.jsonl`
(fields `id`, `title`, `status`, `priority`, `issue_type`, `assignee`,
`created_at`, `closed_at`, `labels`, and `dependencies[]` of
`{depends_on_id, type}` with `type ∈ {blocks, parent-child, related}`) and
answers five questions: what is _ready_, are there dependency _cycles_, how are
my _epics_ progressing, what is my _velocity_, and one human _digest_. Pure
function of (JSONL bytes, injected `--as-of`, `--format`); identical inputs →
byte-identical output; no network, no live `br`, no wall-clock.

**Requirements & acceptance criteria** (each AC names a real pytest node so
`acceptance_mapping` can bind criterion→test):

- **REQ-001 Loader & `IssueGraph` model** _(risk: medium)_ — parse JSONL,
  tolerate trailing newline, ignore unknown fields, fail exit `2` naming the bad
  line on malformed JSON.
  - **AC-001** fixture → exactly N issues / M edges (frozen counts).
  - **AC-002** invalid JSON → exit `2`, stderr contains `line 7`.
- **REQ-002 `ready`** _(high)_ — ready iff `status=="open"` AND every `blocks`
  edge into it originates from a `closed` issue; `parent-child`/`related` never
  gate; sort `(priority asc, id asc)`.
  - **AC-003** exact id set in exact order. **AC-004** reopening a blocker drops
    dependents; closing re-admits.
- **REQ-003 `cycles`** _(high)_ — directed cycles over `blocks` only; each
  reported once as the lexicographically-smallest rotation; self-loop =
  length-1.
  - **AC-005** `A→B→C→A` reported once as `A -> B -> C -> A`; acyclic → 0, exit
    `0`. **AC-006** two disjoint cycles both reported; overlaps not
    double-counted.
- **REQ-004 `epics`** _(medium)_ — per `issue_type=="epic"`, transitive
  `parent-child` rollup: total/closed/pct (floor)/open/blocked; sort by id.
  - **AC-007** `E1` → `total=5, closed=2, pct=40`. **AC-008** childless epic →
    `total=0, pct=100`, no divide-by-zero.
- **REQ-005 `velocity`** _(medium)_ — closed-count per trailing K weekly buckets
  ending at `--as-of` (default 4), half-open UTC; null `closed_at` excluded.
  - **AC-009** `--as-of 2026-06-19T00:00:00Z` → `[3,1,0,2]`. **AC-010** boundary
    close lands in the newer bucket only.
- **REQ-006 `digest` + byte-stability** _(high)_ — compose the four into one
  markdown report, fixed section order.
  - **AC-011** `digest --as-of … --format markdown` byte-identical to a
    checked-in golden. **AC-012** identical bytes across two processes (no
    dict/set ordering nondeterminism).
- **REQ-007 `--format markdown|json`** _(medium)_ — `json` emits locked
  `br_insight.report@1`; unknown format exits `2`.
  - **AC-013** `ready --format json` validates the schema, `kind=="ready"`.
    **AC-014** `--format xml` → exit `2` naming allowed formats.
- **REQ-008 injected `--as-of` clock** _(high)_ — no command reads wall-clock.
  - **AC-015** grep of non-test modules for
    `datetime.now|time.time|utcnow| date.today` → zero hits. **AC-016** same
    `--as-of` → same bytes; different → different bucket counts.

**Locked key interfaces** (the only two cross-slice contracts; ContractLock
freezes these; evolution mints `@2`, never mutates `@1`):

- **`Issue` / `IssueGraph`** — immutable `Issue` dataclass (`id`, `title`,
  `status: open|closed|deferred`, `priority: int`, `issue_type`, `assignee?`,
  `created_at`, `closed_at?`, `labels: tuple`); `IssueGraph` holds `issues` +
  precomputed `blocks_edges`/`parent_edges`/`related_edges` sets. Every command
  reads `IssueGraph`; none re-parse JSONL.
- **`br_insight.report@1`** —
  `{schema_version, generated_as_of, kind, source:{ path,issue_count,edge_count}, data:{…}}`;
  per-kind `data` arrays sorted deterministically; emitted with
  `sort_keys=False, separators=(",",":")` so JSON is byte-stable.

**Non-goals.** Read-only; no live `br`; no network; no TUI; no
create/edit/sync/auth/config/plugins; nothing dependent on wall-clock, locale,
or iteration order.

**Base-repo scaffold (sandbox seed).** `pyproject.toml` (package `br_insight`,
console-script, stdlib-only + pytest, Python ≥3.11);
`src/br_insight/{__init__, cli,model}.py` (the locked `model.py` ships in the
seed — it _is_ the interface);
`tests/test_{loader,ready,cycles,epics,velocity,digest,format,determinism}.py`
with the AC node-ids as failing stubs (red→green); `tests/fixtures/issues.jsonl`
(~20 issues: a ready chain, a fully-blocked issue, an epic with 5 children/2
closed, dated `closed_at`s over 4 weeks) + `tests/fixtures/cyclic.jsonl` (the
planted cycle); `tests/golden/digest_2026-06-19.md`; a generated `AGENTS.md`
stating the read-only/no-network/injected-clock invariants + `pytest -q` as the
verification command.

**Planted ambiguity (OFF for first green run).** REQ-002 is intentionally silent
on whether a `deferred` blocker gates its dependents ("blocker satisfied" =
`closed` only, or `closed OR deferred`?). The literal wording resolves it, and
the first-run fixture contains no deferred blocker on a ready chain — nothing to
ask. M6 flips it on (add a deferred-blocker chain + soften the wording) to test
whether the Interrogator raises the question instead of letting the agent
silently choose.

**Slice shape (~7 slices, a clean diamond).** SLICE-001 loader+model+scaffold
(root, all depend on it) → SLICE-002 `ready` / 003 `cycles` / 004 `epics` / 005
`velocity` (4 independent forks, disjoint conflict domains) → SLICE-006 `digest`
(join, depends on all four) → SLICE-007 `--format json` + `report@1` emitter +
determinism sweep (terminal, edits every command's output path; autonomy L2).
Only `model.py` and `report@1` are cross-slice contracts — exactly two interface
surfaces for ContractLock to freeze.

---

## Appendix B — grounding

Code touch-points and module/line references for §2 and §5 were derived from a
read of: `lib/conveyor/{run_slice,station,readiness}.ex`,
`lib/conveyor/eval/{golden_thread,agent_station,verify_station,work_graph_to_station_plan,mutant_gauntlet,lift_duel,scorecard}.ex`,
`lib/conveyor/jobs/{run_gate,run_gate_canary}.ex`,
`lib/conveyor/agent_runner/codex.ex`,
`lib/conveyor/{context_scout,baseline_health,acceptance_calibration}.ex`,
`lib/conveyor/evidence/recorder.ex`,
`lib/conveyor/contract_forge/contract_author.ex`,
`lib/conveyor/planning/{pilot_selection,pilot_execution,slice_dependency}.ex`,
`lib/conveyor/factory/{slice,station_effect}.ex`,
`test/support/bridge_fixtures.ex`, and the schemas under `docs/schemas/`.
