# Conveyor — ROADMAP (v2)

> **Purpose.** The single source of truth for _where Conveyor is, where it's going, and in
> what order._ Grounded in a static code assessment (2026-06-21) and then **adversarially
> red-teamed** against itself (see `ROADMAP-REVIEW.md` for the audit trail and the
> corrections that produced this v2). When this doc and any older plan disagree, **this doc
> wins** until superseded.
>
> **Evidence convention.** Claims are tagged: **[verified-static]** = confirmed by reading
> code (file:line); **[needs-run]** = a runtime claim (crash, pass-rate, hang, "never
> fires") _inferred from static reading but NOT yet reproduced by executing_; **[provisional]**
> = a target/number chosen as a starting point, not derived. Nothing in the underlying audit
> was executed — M0 includes actually running the affected paths to convert [needs-run] →
> verified.
>
> **North star.** Hand Conveyor a large plan → it decomposes it into a dependency-ordered
> work-graph of contract-bearing slices → a fleet of AI agents builds the whole thing
> end-to-end, unattended, with parallelism for speed. The human reviews a morning digest and
> a small "needs-judgment" queue.
>
> **Strategic call (ratified 2026-06-21).** Get a **width-1, strictly serial, but _fully
> autonomous_** loop working rock-solid on real plans **first**; introduce **cross-slice**
> parallelism only after the serial loop clears the exit bar (§4). (Note the scoping fixed in
> v2: _within-slice_ speculative racing is a reliability lever that lives **inside** Track A —
> see Principle 5 and M2.)

---

## 1. Executive summary — the honest state

Conveyor has a large, sophisticated substrate (**383** `lib` modules [verified-static; the
v1 "≈230" figure was wrong], 307 test files, 27 ADRs, ~120 schemas). The headline is **not**
"a world-class judge bolted to a skeleton defendant." It is blunter:

> **Nothing works end-to-end yet.** The _verifier_ has extensive scaffolding but is largely
> **non-functional / under-wired**; the _execution loop_ has neither the scaffolding nor the
> function. The hard, durable half (trustworthy autonomous adjudication) was built first —
> a **deliberate and defensible** bet, since you cannot calibrate a trust gate without first
> building one. The task now is to **activate and finish the verifier _and_ build the loop
> that exercises it** — wiring what's dormant, finishing what's half-built, without inventing
> new gate _concepts_.

The findings that drive the plan (all [verified-static] unless tagged):

1. **The verifier is larger than the wired loop — by ~2.3–4× like-for-like** (whole-subsystem
   vs whole-subsystem), up to ~8× only if you pair the broadest verifier bucket against the
   narrowest loop bucket. _(The v1 "~7.5× / 12k vs 1.6k LOC" was one extreme of that range
   presented as a point measurement — corrected.)_ More important than size: the verifier is
   **not functional** — 4 of 14 gate stages wired on the live path; the IntegritySentinel
   gate **requires** only 2 probes and supplies exactly those 2; abstain has never been
   observed to fire in a normal run [needs-run]; calibration is hardcoded constants.
2. **The loop's two halves have never been joined in one run.** The production `SerialDriver`
   has only run with canned `ReferenceSolution` patches (7/7 Beads-Insight slices accepted —
   but that measures the _patch applier_, not an agent). The real Codex agent has only run
   through **non-`SerialDriver` eval paths** (one of which is `Eval.GoldenThread`). Joining
   them is the keystone (M1).
3. **The closers are dormant.** `AttemptLoop`, `RaceConductor`, `MidflightCheck`,
   `AmendmentRouter`, `PlanFoundry`/`CodexDrafter` each have **zero production callers** (one
   test file each). Today a single non-passing slice parks and **halts the whole plan**.
4. **No autonomous orchestration.** **Zero `Oban.insert`/`insert_all` calls** in `lib/`; the
   "orchestrator" is a synchronous, human-invoked mix task.
5. **No autonomous decomposition.** `mix conveyor.run` _requires_ a hand-authored
   `conveyor.plan@1` contract; `Decomposer.propose` reads only `List.first(requirements)` and
   emits one hardcoded slice; the dependency graph is a fabricated linear chain.

**Implication:** activate + finish the verifier, join + close the loop, then add decomposition,
then parallelism — earning trust at each step against a stated bar.

---

## 2. Where we are — subsystem map

Legend: **maturity** = built-out · **functional** = actually works on the live `mix
conveyor.run` path (not just "code exists").

| Subsystem | Maturity | Functional on live path | One-line reality |
|---|---|---|---|
| **Core execution loop** | high | **partial** | Autonomous on the _decision_ side; only ever closed with **canned patches**, never an agent. Single-attempt: any non-accept **halts** the plan. |
| **Planning / decomposition** | low–partial | **no** | Requires a hand-authored `conveyor.plan@1`. `Decomposer` is content-blind. Dep-graph is a fabricated linear chain. `PlanFoundry`/`CodexDrafter` wired to no command. |
| **Verification gate / trust** | high surface, **low function** | **partial (degenerate)** | Rich scaffolding runs but collapses to a **binary 4-stage gate + auto-accept**. `TrustScore` defaults unmeasured→trustworthy. Of 10 catalogued integrity probes the gate **requires 2 and has 2**; the other 8 are optional/aspirational (not "80% blind" — but also not adding signal). Abstain not observed to fire in normal runs [needs-run]. |
| **Test Architect / contract forge** | high | **partial** | Deterministic projections of fields the human already wrote — no independent test _authoring_, no falsifier _execution_. `test_architect/*` disconnected. |
| **Evidence / replay / ledger** | high | **partial** | Ledger + recorder + blob store load-bearing; but `replay_fidelity` is **hardcoded `"matched"`** (a vacuous signal), the outbox relay is never invoked, cassettes/replay are eval-only. |
| **Autonomy / self-heal / recovery** | high | **no** | Rich library (`AttemptLoop`, `Recovery`, `EmergencyStop`, watchdog primitives) — almost none wired. Live loop has zero retry, zero watchdog, halts on first failure. |
| **Orchestration / runtime** | partial | **no** | Synchronous human-invoked mix task. **Zero `Oban.insert` calls.** Conductor children are no-op skeletons; Docker isolation unwired; no crash-recovery (state in process memory). |
| **Eval program (Rungs 0–2)** | real | partial | Real, CI-gated, runs real pytest. Only **3 of 8 mutants** covered e2e; `mix conveyor.eval.lift` **crashes** [needs-run] (cause: `load_reports` decodes `usage.json` alongside duel reports — _not_ a "glob collision"; there is no glob). |
| **ADRs 01–23 / 24–27** | — | mostly / **no** | Evidence-kernel + serial-loop ADRs functional; the four "autonomy" ADRs (24–27) are test-covered islands with zero callers. |

**The one real lift measurement (read carefully):** the committed `eval/lift/seed.json` duel
shows **pass@1 lift Δ = 0.0** — but **both arms passed 3/3 (100%)** on one trivial greenfield
task (n=3, k=1, 95% CI [0.292, 1.0]). That is **"the task was too easy to show any signal,"
not "Conveyor failed to help."** It cannot bear weight in either direction. _(v1 over-read
this — corrected.)_

```
  DREAM:    prose plan ─▶ DECOMPOSE ─▶ dep-graph ─▶ [agent builds each slice] ─▶ gate ─▶ merge ─▶ done (unattended)
  REALITY:               ✗ stub        ✗ linear      A) prod loop: canned patches    degenerate    ✗ halts on
                       (hand-author)   (fabricated)  B) real agent: eval-only paths   (4/14 stages)   1st fail
                                                     — A and B never joined —
```

---

## 3. Operating principles for this era (durable)

1. **Activate _and finish_ the verifier; freeze new gate _concepts_.** The verifier is
   under-wired, not over-built — much of it is half-finished (missing producers, hardcoded
   calibration, dormant probes). So "wiring" here legitimately includes **net-new completion
   work** (e.g. M4). The freeze is narrow and real: **do not add new gate _concepts/stages_**
   to a gate that doesn't yet function. _(v1 sloganed "don't build more," which contradicted
   M4 — corrected.)_
2. **The real dragon is autonomous _duration_, not parallelism.** A long unattended serial
   chain dies of drift/error-accumulation and of one stuck slice halting the train. Hardening
   "serial" means hardening _long-horizon_ autonomy (rework, skip-and-continue, watchdog,
   drift detection, resumability).
3. **Stage on plan _size_.** Small (3–8) → medium (15–40) → large. Drift only shows at scale.
   Note: a "large" rung lives in Track B / the north star, not in a Track-A milestone.
4. **Architect parallel-ready while running serial.** A _missing_ dep-graph edge (false
   independence) detonates in parallel though it's invisible serially; a _spurious_ edge just
   over-serializes (harmless now). The "validate the graph as if parallel" insurance (build
   each slice against deps' frozen interface stubs — itself real work, ~ADR-18) only has a
   _computed_ graph to validate **from M5 on**; before that (M3) the graph is small and
   hand-authored, so the residual risk is low. Keep the seams (per-slice isolation, a
   merge-queue seam that's a no-op fast-forward at width 1) so going parallel is a cap change,
   not a re-plumb.
5. **Two kinds of parallelism — don't conflate them.** **Cross-slice fleet** parallelism
   (Track B) is a _throughput_ multiplier; defer it until the single-slice verdict is
   trustworthy, because false-passes _compound_ across a fleet. **Within-slice speculative
   racing** (ADR-25) is a _reliability/capability_ lever that can make a hard slice close —
   it belongs **inside Track A** (an option from M2). _(v1 declared "parallelism is only
   throughput" and then used within-slice racing as a quality lever — corrected.)_
6. **Measure value over bare-agent on the differentiating axis.** pass@1 is the wrong metric
   (and unmeasurable as signal on trivial tasks — see §2). Conveyor's value is **trustworthy
   unattended completion + defects-caught** — which are _verifier outputs_, so they are only
   measurable once M4 activates the gate. Hence verifier activation is itself the load-bearing
   evidence step, not a distraction from it.

---

## 4. The exit bar — "serial is done" (gates Track B)

> A bar keeps "harden it first" from expanding forever. **But these numbers are mostly
> [provisional]** — chosen as starting targets, not derived — and must be calibrated on real
> runs (M0–M6). Honesty about their status _is_ the rigor; pretending they're derived would
> be false rigor. Track B (cross-slice fleet) does not start until all hold.
>
> **Corpus caveat (load-bearing):** every bar metric below is measured on the **single
> Beads-Insight greenfield pure-logic target** — about the easiest possible autonomous-coding
> task (deterministic, golden-file oracle, reference patches committed). The bar therefore
> proves "serial autonomy works _on that class of task_," **not** general capability;
> multi-archetype + brownfield generalization is explicitly OUT of this bar and unproven
> (deferred, §7). A small corpus of ≥3 distinct greenfield targets before the medium-plan run
> would materially de-risk over-fitting to Beads-Insight.

- [ ] **Joined seam:** the M1 work has produced a real-agent run through the production
  `SerialDriver`, captured as a cassette and replayed in CI. _(This proves **wiring
  stability**, not agent reliability — see M1.)_
- [ ] **Autonomous decomposition is in the loop:** `mix conveyor.author "intent"` → a
  computed `conveyor.plan@1` → unattended run. **This is an M5 deliverable, so M5 is a
  precondition of this bar** (fixed in v2 — the bar cannot be met at M4).
- [ ] **Unattended medium plan:** a **≥20-slice** [provisional; sits in the §3 "medium 15–40"
  band — see M6] real plan reaches 100% green, fully unattended, **live** (fresh agent
  invocations, not cassette replay — replay only tests determinism), **5 consecutive runs**
  [provisional].
- [ ] **First-pass gate success ≥ 70%** and **material-dispute < 20%** — note these are
  **inherited "INITIAL HYPOTHESES"** from the Phase-2 plan (explicitly "subject to revision"),
  **not derived**; the one prior real gate run reportedly missed both [needs-run]. Treat as
  provisional and recalibrate.
- [ ] **Parked rate < 15%** [provisional] **AND** an absolute cap of **≤ N judgment-items/day
  for one reviewer** at target plan size (set N from real M6 data — the solo-reviewer
  bandwidth assumption must be quantified, not assumed).
- [ ] **Gate honesty:** `MutantGauntlet` runs the canary corpus through the real
  `test_execution` stage in CI with a **zero false-pass** rate on the behavioral mutant set
  (gated by `conveyor.eval.scorecard --gate`); integrity-discrimination in CI. _(Full
  static-stage mutant coverage — policy/contract/run_check/code_quality — is M4.)_
- [ ] **Survivability:** watchdog bounds every agent call; stuck slices are reaped/routed, not
  hung; a crashed run **resumes** from durable state.
- [ ] **Demonstrated lift** on the differentiating axis (defects-caught / honest abstention,
  not pass@1) over bare-agent — measurable only after M4.

---

## 5. The milestone roadmap

Sizes are rough solo-dev T-shirts (**S** ≈ days · **M** ≈ 1–2 wks · **L** ≈ 3–5 wks · **XL** ≈
6+ wks) — directional, not commitments. "Wire existing" is genuinely cheaper than net-new, but
**not free** (it still needs tests, real-agent runs, and de-bugging the dormant code).

> **br note:** M0–M3 are filed under epic `software-factory-ai-jwxp`. The **resequencing
> below (M5 decomposition moved _before_ the medium-plan milestone; within-slice racing pulled
> into M2) only affects M4+**, which are not yet filed — M0–M3 are unchanged.

### TRACK A — serial, fully autonomous, to the bar

#### M0 — Honesty cleanup **(S)**
Make the instruments trustworthy, and **execute the [needs-run] claims** to confirm them.
- Reproduce + fix the `eval.lift` crash. **Real cause:** `load_reports` decodes _all_ `.json`
  (incl. `usage.json`) as duel reports → filter by `schema_version` (not a "glob" fix).
- **Gate honesty [w49f]:** retired the misleading `conveyor.gate_canary` mix task (it ran an
  empty `[]` gate → "passed" everything). Real gate-honesty discrimination is `MutantGauntlet`
  (canary corpus → real pytest → `test_execution` stage → real false-pass rate), already
  CI-gated via `conveyor.eval.scorecard --gate`. Full static-stage coverage deferred to M4.
- **Fix the P1 ledger-bypass bug [dr1m.1.1]:** the gate `:gate` transition always fails on the
  live path → a silent raw-write fallback **bypasses the state machine + ledger**. M1's
  "recorded-vs-replayed digest" and the whole evidence substrate are unreliable until this is
  fixed — so it is M0 scope, not deferred.
- Reconcile contradictory docs [dr1m.10]; run the affected paths and tag every prior runtime
  claim verified or refuted.
- **Exit:** green eval-lift in CI; MutantGauntlet (behavioral) gate-discrimination CI-gated;
  the empty-gate canary footgun removed; the [needs-run] tags in this doc are resolved.

#### M1 — Join the seam: real agent through the production loop **(M) — KEYSTONE**
- Run real Codex through `PlanRunner`/`SerialDriver` (6 stations + 4 gate stages + `Finalizer`)
  on the Beads-Insight plan; capture as a cassette; add a committed CI test (removes the
  `Process.put` stub). Back "reproducibly" with a **real recorded-vs-replayed digest compare**
  (the eval `ReplayEngine`), **not** the hardcoded `replay_fidelity:"matched"` field.
- **Exit (precise):** the joined seam executes end-to-end and **the recorded run replays
  deterministically in CI (wiring stability).** This does **not** prove the stochastic agent
  reliably succeeds — that's M3/M6 with live runs.
- **Kill/pivot trigger:** if joining reveals the station/gate contract is structurally wrong
  for real-agent output (not a quick fix), **stop and redesign the loop contract before M2** —
  do not paper over it with rework.

#### M2 — Close the loop on ONE slice: wire the dormant closers **(M)**
- Wire `AttemptLoop`/`ReworkSynthesizer` into `SerialDriver` (rework-on-fail, bounded budget)
  [dr1m.9 — decision is "wire"]. Wire ADR-26 `AmendmentRouter` (fix dr1m.4.1 first). Wire
  ADR-24 `MidflightCheck` [tracked in dr1m.2 — already in progress]. Add a **watchdog/timeout**
  around the agent call (today unbounded).
- **Optional reliability lever (Principle 5):** within-slice speculative racing (ADR-25
  `RaceConductor`, fix dr1m.3.1 crash first) [dr1m.3] — available here to help hard slices
  close; cost-governed; _not_ Track B.
- **Exit:** a slice can fail→rework→pass, or fail→escalate/park, **without halting**.

#### M3 — Unattended on a SMALL multi-slice plan (3–8) **(M)**
- Skip-and-continue over the dep subgraph; durable resumability (replace in-memory
  `reduce_while`); per-slice workspace isolation (branch/worktree + diff-policy commit) — the
  parallel-ready seam.
- **Exit:** a real 3–8 slice plan completes fully unattended with **live** Codex, surviving an
  induced slice failure, N consecutive runs. _Honesty caveat: "green" here = passes the
  M3-level **4-stage** gate (real `TestExecution` does catch an induced test failure);
  **trustworthy, false-pass-resistant green** (abstain + integrity signals) does not exist until
  M4 — so M3 "100% green" can still hide a subtly-wrong-but-tests-pass slice._
- **Kill/pivot trigger:** if drift/error-accumulation across even 8 slices proves
  unmanageable, scope down the autonomy claim before investing in M4+.

#### M4 — Activate + finish the gate **(L — the heaviest Track-A milestone; this is net-new verifier completion, not mere wiring)**
- Wire the dormant IntegritySentinel producers; write `corpus_pass_rate` + `replay_divergence`
  from production stations (so `TrustScore` stops defaulting unmeasured→trustworthy); make
  abstain fire on real signals; replace hardcoded `replay_fidelity`.
- **Network-isolated gate verification** (for hermeticity) — see D1: this needs a
  network-blocking sandbox; Docker is the wired path, but `unshare -n` / an egress policy is an
  alternative. _Distinct from agent isolation._
- Extend `MutantGauntlet` to the **static-stage** mutants (policy/contract/run_check/
  code_quality — the `deferred_static_stage` cases) so the full canary corpus discriminates,
  not just the behavioral subset; keep it CI-gated. Re-validate integrity-discrimination in CI.
- **Exit:** the live gate measurably discriminates (zero false-pass on mutants); abstain fires
  for real; first-pass-gate-success + dispute-rate **measured** (meeting the §4 targets is
  owned by M2's rework + this milestone's gate work, iterated).

#### M5 — Autonomous decomposition **(L)** _(moved earlier in v2 — it's a precondition of the §4 bar and of M6's large plans)_
- Wire `PlanFoundry`/`CodexDrafter` into `mix conveyor.author "intent"` → `conveyor.plan@1`.
- Replace the content-blind `Decomposer` stub with a real one. **Compute real
  `work_dependencies`** from interface bindings (`SliceDependency`/`InterfaceGraph`) — this is
  what gives Principle 4 a real graph to stub-validate. Fire the Interrogator (ADR-27) on
  genuine ambiguity.
- **Exit:** prose intent → autonomous decomposition → a runnable plan; the dep-graph is
  _computed_ and stub-validated.

#### M6 — Long-horizon autonomy + medium plan **(L)**
- Drift/no-progress detection; Convergence Sentinel (anti-thrash); Repeat-Offender escalation;
  enforce `EmergencyStop` + activate `BudgetReservations`; retention/GC sweeper (ADR-10); wire
  the morning digest + parked-queue triage (`ParkedQueueLive`).
- Agent runs inside the M4 container here (blast-radius — D1 #1).
- **Exit:** a **medium plan (15–40 slices)** — now feasible because M5 can author it —
  completes unattended overnight, live, surviving stuck/runaway conditions. This is the
  milestone that produces the §4 bar's ≥20-slice / 5-run result.

**→ Track A exit gate = §4 bar fully met (M5 + M6 are both required for it). Only then Track B.**

### TRACK B — cross-slice parallelism

#### M7 — Cross-slice fleet **(XL)**
Dispatcher + WorkerPool + MergeQueue + Governor; **activate the dormant Oban/Conductor
substrate** (first-ever `Oban.insert`; Conductor children; Cron/Pruner plugins); container per
agent (reusing the M4 image); branch-per-slice → integration gate on `dev` → phase-gate to
`main`; then BEAM distribution. _(Within-slice racing already landed in M2.)_

---

## 6. Cost, dogfooding & self-hosting (new in v2)

- **Cost/budget.** Every Track-A milestone burns real agent tokens; M3/M6 (repeated full-plan
  live runs) and M7 (N-way racing) are the expensive ones. **Set a dev-phase not-to-exceed
  budget and a rough per-milestone token estimate** before M3; cost is a scheduling input, not
  an afterthought (the project's own economic-governor thesis).
- **How Conveyor gets built (dogfooding).** **M0–M5 are hand-built** (with Claude/Codex as
  assistants, not as the factory): the factory cannot author its own plans until M5 and cannot
  safely touch a real repo until the M4 container exists. **Dogfooding starts no earlier than
  M6**, advisory-only, against sterile targets.
- **Self-hosting capstone.** "The factory builds the factory" (RADICAL-LEVERAGE idea #12,
  explicitly "earn it last") is the truest test and the north star's proof. It is a **post-bar
  capstone (call it M8)**: advisory/read-only runs against this repo's own `.beads/`, earning
  auto-merge as trust accrues. Named here so it stops being a one-word parenthetical.

---

## 7. Deferred backlog, risks & decisions

**Deferred (not on the critical path):** Verifier-as-product / Findings-to-Fix on _external_
repos. **OPEN DECISION (parked for M4, non-blocking — does not gate M0):** run the
_activated_ gate (M4) against a handful of known-buggy external commits as a cheap
catch-rate **falsification of the core thesis**, vs. keep fully deferred. _Recommended:_ the
M4 probe — but it only yields signal _after_ M4 activates abstain/integrity (the current
degenerate gate would mislead), so it can't actually come earlier; Scar Ledger / FailureMemory + pgvector recall; Divergence
Bisector; Rung-3 honesty eval (fold into M4); multi-archetype + brownfield (today: single
greenfield pure-logic Python); DSPy/GEPA optimization; CredentialPool/CAAM.

**Risks:** **R1** — value over bare-agent is unmeasured and only becomes measurable at M4;
treat M4 as load-bearing evidence, not overhead. **R2** — two execution paths until M1 joins
them. **R3** — real-repo safety needs M3 isolation + the M4 container. **R4** — decomposition
quality (M5) is the load-bearing artifact for the whole dream; expect iteration. **R5
(method)** — this plan rests on a _static_ audit with leading-prompt risk; the conclusions
most exposed (drift behavior, "abstain never fires") are exactly the ones a run would settle —
hence M0 executes them.

- **D1 — Agent isolation: DECIDED (staged), with corrected rationale.** "Isolation" bundles
  five jobs; **Docker is the path we have wired, not the only path, and is _not_ strictly
  required for the zero-false-pass bar** (corrected from v1):
  1. **Blast-radius** (host/repos/creds) — serial, scales with unattendedness → **M6**.
  2. **Hermeticity** — needs a **network-blocking sandbox**; 5 of 6 hermeticity controls are
     already satisfied by the host `:local` backend, only `network:blocked` is missing.
     Docker supplies it; so does `unshare -n` / an egress policy. **Hermeticity is a property
     of the GATE's verification re-run, not the agent's build step.** Missing it makes the
     gate **abstain more** (`not_assessed` is non-blocking → park; honest, lower throughput) —
     it does **not** cause false-passes. The behavioral zero-false-pass metric already runs on
     the host. → wanted at **M4**.
  3. **Clean-slate teardown** — M3–M4.  4. **Concurrency isolation** — **parallel-only → M7.**
     5. **Network egress** — M4/M6.

  **Plan:** host `codex --sandbox` through M0–M3; introduce the network-isolated gate at M4
  and the containerized agent by M6, by _wiring existing_ `DockerRunner` + `ToolchainRunner`
  hermetic backend + `Sandbox.Reaper`, **one pinned image shared by agent + gate** (else
  "passes here, fails there" returns); that image becomes the M7 per-worker container.
  **Open sub-decision that sets urgency:** what repos do unattended runs target? Sterile →
  host sandbox tolerable longer; real/valuable → blast-radius pulls the container earlier.
- **D2 — `br` tracking: reconciled.** M0–M3 under epic `jwxp`. Corrections applied:
  `dr1m.2` (ADR-24, in_progress) is the canonical issue — duplicate `onfq` closed and `dr1m.2`
  linked under M2; `dr1m.9` retitled to the decided "wire" action; `dr1m.3` (ADR-25 racing)
  linked as M2's optional lever; epic `sgp` (deferred Phase 0–8) annotated as superseded by
  this roadmap. M4–M8 filed as they near.

---

## 8. Mapping to prior planning

- **Supersedes** the abstract "Phase 0–8" planning list (formerly `docs/BRAINSTORM.md`, now
  removed — recoverable from git history) and the deferred `br` epic `sgp.2–7` (annotated
  in-tracker). Rough map: Phase 1→M1; Phase 2→M5; Phase 3 (parallel
  fleet)→M7; Phase 4 (verification pyramid)→_M4 finishes/activates it_; Phase 5
  (self-healing)→M2/M3/M6; Phase 6→M6; Phase 7→deferred §7; Phase 8→M7.
- **ADRs 01–23** largely functional. **24–27** are the dormant closers this roadmap wires:
  M2 (24/25/26), M5 (27). The **raw-leverage thesis** ("activate the dormant verifier — it's
  an engine, not a product") is the spine; v2 corrects the v1 overreach that read "activate"
  as "freeze / stop building."

---

## 9. Provenance & confidence

This roadmap = a 16-agent **static** code audit (2026-06-21) + an adversarial self red-team
(15 agents) that corrected six classes of defect (factual errors, the over-built→under-wired
reframe, M5/M6 resequencing, exit-bar false rigor, the Docker necessity overstatement, and
tracker duplication). Full trail: **`ROADMAP-REVIEW.md`**. Headline facts survived a _blind_
re-verification (loop not closed, real agent never through production loop, decomposer is a
stub, zero `Oban.insert`, dormant closers). The numbers (LOC ratio, the exit-bar thresholds)
are **ranges/provisional**, not measurements. Anything tagged [needs-run] is resolved in M0.

_Last updated: 2026-06-21 (v2, post red-team)._
