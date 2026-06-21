# Conveyor — ROADMAP

> **Purpose.** The single source of truth for _where Conveyor is, where it's
> going, and in what order._ Grounded in an evidence-based code assessment
> (2026-06-21, 16-agent audit of the live execution path), not in aspirational
> docs. When this doc and any older plan disagree, **this doc wins** until
> superseded.
>
> **North star.** Hand Conveyor a large plan → it decomposes the plan into a
> dependency-ordered work-graph of contract-bearing slices → a fleet of AI
> agents builds the whole thing end-to-end, unattended, with parallelism for
> speed. The human reviews a morning digest and a small "needs-judgment" queue.
>
> **Current strategic call (ratified 2026-06-21).** Get a **width-1, strictly
> serial, but _fully autonomous_** loop working rock-solid on real plans
> **first**; introduce parallelism only after the serial loop clears a _numeric_
> exit bar (§4). Parallelism is a throughput multiplier on a proven loop — not a
> capability — and you cannot parallelize a loop that does not yet reliably
> close.

---

## 1. Executive summary — the state of the union

Conveyor has accumulated an enormous, genuinely sophisticated substrate (≈230
`lib` modules, 307 test files, 27 ADRs, ~120 canonical schemas). **The depth is
real, but it is overwhelmingly concentrated on the _verifier_, while the
_end-to-end execution loop_ — the thing that actually takes a plan to done
unattended — is thin and, at its center, not yet joined.**

The three findings that drive this entire roadmap:

1. **The verifier is ~7.5× the execution loop and dramatically more mature.**
   ~12k LOC of judge vs ~1.6k LOC of wired loop core; 14 gate stages built, 4
   wired. (Audit 6: _confirmed_.)
2. **The headline loop's two halves have never been joined in one run.** The
   production `SerialDriver` loop has only run with canned `ReferenceSolution`
   patches; the real Codex agent has only run through a _separate, slimmed_ eval
   harness (`Eval.GoldenThread`). The single most valuable next action is to
   **join them.** (Audit 1: _partially-real_.)
3. **The closers exist but are dormant.** `AttemptLoop` (rework/retry),
   `MidflightCheck` (ADR-24), `AmendmentRouter` (ADR-26), `RaceConductor`
   (ADR-25), `PlanFoundry`/ `CodexDrafter` (ADR-27) are all **built, tested, and
   unwired** — zero production callers. Today a single non-passing slice parks
   and **halts the whole plan.**

**Implication:** the next era is not "build more." It is **wire what exists,
join the seam, and harden for unattended duration** — exactly the "activate the
dormant verifier" thesis already on record.

---

## 2. Where we are — evidence-grounded subsystem map

Legend: **maturity** = how built-out · **wired** = actually on the live
`mix conveyor.run` execution path (the only path a real autonomous run would
take).

| Subsystem                                                                           | Maturity        | Wired into live loop     | One-line reality                                                                                                                                                                                                                               |
| ----------------------------------------------------------------------------------- | --------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Core execution loop** (PlanRunner→SerialDriver→6 stations→4-stage gate→Finalizer) | high            | **partial**              | Real & autonomous on the _decision_ side; but only ever closed with **canned patches**, never a real agent. Single-attempt: any non-accept **halts the plan**.                                                                                 |
| **Planning / decomposition / dep-graph**                                            | low–partial     | **no**                   | `mix conveyor.run` **requires a hand-authored `conveyor.plan@1` contract**. `Decomposer.propose` is a content-blind stub. Dep-graph is a **fabricated linear chain**, not computed. `PlanFoundry`/`CodexDrafter` not connected to any command. |
| **Verification gate / trust**                                                       | very high       | **partial (degenerate)** | Rich scaffolding runs, but collapses to a **binary 4-stage gate + auto-accept**: `TrustScore` defaults unmeasured→trustworthy; only 2/10 IntegritySentinel probes have producers; abstain never fires in a normal run.                         |
| **Test Architect / contract forge**                                                 | high            | **partial**              | `ContractAuthor`/`FalsifierForge` are **deterministic projections** of fields the human already wrote — no independent test _authoring_, no falsifier _execution_. `test_architect/*` is a disconnected island.                                |
| **Evidence / replay / ledger**                                                      | high            | **partial**              | Ledger + recorder + blob store are load-bearing; but `replay_fidelity` is **hardcoded `"matched"`**, the event outbox relay is **never invoked**, cassettes/replay are eval-only.                                                              |
| **Autonomy / self-heal / recovery**                                                 | high            | **no**                   | Rich library (`AttemptLoop`, `Recovery`, `FailureDiagnosis`, `EmergencyStop`, watchdog primitives) — **almost none wired.** Live loop has zero retry, zero watchdog, halts on first failure.                                                   |
| **Orchestration / runtime**                                                         | partial         | **no**                   | "Orchestrator" = a **synchronous human-invoked mix task.** **Zero `Oban.insert` calls.** Conductor children are no-op skeletons; Oban `plugins: []`; Docker isolation unwired. No crash-recovery (state in BEAM process memory).               |
| **Eval program (Rungs 0–2)**                                                        | production-real | partial                  | Real, CI-gated, runs real pytest. But only **3 of 8 mutants** covered e2e; `mix conveyor.eval.lift` **currently crashes** (glob collision); one real seed, **pass@1 lift = 0.0**.                                                              |
| **ADRs 01–23**                                                                      | —               | mostly wired             | Evidence-kernel + serial-loop ADRs built into the live path.                                                                                                                                                                                   |
| **ADRs 24–27**                                                                      | —               | **no**                   | Newest "autonomy" ADRs exist only as **test-covered islands with zero callers.**                                                                                                                                                               |

**The severed seam, visually:**

```
  HEADLINE DREAM:  prose plan ─▶ DECOMPOSE ─▶ dep-graph ─▶ [agent builds each slice] ─▶ gate ─▶ merge ─▶ done (unattended)
                                  ▲                          ▲                            ▲
  REALITY:           ✗ not wired ─┘          ✗ fabricated ───┘     two halves never joined ┘     ✗ halts on 1st fail
                     (hand-author              (linear chain,      A) prod loop: canned patches    (no rework wired)
                      the contract)             not computed)      B) real Codex: slimmed eval harness
```

---

## 3. Operating principles for this era (durable; apply to every milestone)

1. **Freeze net-new verification surface area.** The judge is over-built
   relative to the loop. Until the loop closes unattended, the gate budget is
   spent **wiring/activating what exists** (dormant IntegritySentinel producers,
   calibration, corpus signal), never adding new gate concepts. ("Activate the
   dormant verifier, don't build more.")
2. **The real dragon is autonomous _duration_, not parallelism.** "One slice at
   a time until done" on a real plan is a long unattended chain. The failure
   mode that kills it is **drift / error-accumulation** (slice 47 building on
   slice 12's subtly-wrong-but-green output) and **a single stuck slice halting
   the train.** Hardening "serial" means hardening _long-horizon_ autonomy
   (rework, skip-and-continue, watchdog, drift detection, resumability) — not
   "make one slice green."
3. **Stage on plan _size_, not just width.** Turn one dial at a time: close the
   loop unattended on a **small** plan (3–8 slices) before a **medium** one
   (15–40) before reaching for **large**. Drift only appears at scale; meet it
   on a plan you can still hold in your head.
4. **Architect parallel-ready while running serial.** Serial execution _hides
   dependency-graph bugs_ — a wrong/missing edge quietly works serially but
   detonates the instant you go parallel. So: keep the parallel seams now
   (branch/worktree per slice, a merge-queue seam that's a trivial fast-forward
   at width 1, interface contracts locked at plan time) and **validate the
   dep-graph as if parallel** (build each slice against its deps' frozen
   interface stubs). Flipping to parallel must be _raising a cap from 1→N_, not
   a re-plumb.
5. **Measure Conveyor's value over bare-agent, or stop.** The one real
   measurement showed **pass@1 lift = 0.0.** That's a yellow flag, not a verdict
   (n=3, single greenfield seed) — but it forces the question: _what does
   Conveyor do that "just run Codex" can't?_ The answer is almost certainly
   **trustworthy unattended completion + defects-caught**, not raw pass@1. The
   exit bar (§4) therefore measures **unattended completion rate and
   gate-honesty (zero false-pass)**, and every milestone must move one of those
   numbers.

---

## 4. The exit bar — "serial is done" (a _number_, decided up front)

> This project has a strong gravitational pull toward verification depth.
> Without a measurable bar, "harden it before parallelism" expands to fill all
> available time. The discipline is **"serial to a _defined_ bar, then
> parallel."** Parallel work (Track B) does not start until **all** of the
> following hold:

- [ ] **Joined seam:** a committed CI test runs `mix conveyor.run` → real
      `SerialDriver` → **real Codex adapter** (recorded cassette) end-to-end.
      (Kills the "stubbed by `Process.put`" gap.)
- [ ] **Unattended medium plan:** Conveyor takes a hand-authored **≥20-slice**
      real plan to **100% green, fully unattended (zero mid-run human commands),
      5 consecutive runs.**
- [ ] **Autonomous front-end:** a prose intent → `mix conveyor.author` →
      decomposed `conveyor.plan@1` → that same unattended run, for at least one
      real plan.
- [ ] **First-pass gate success ≥ 70%** (currently unmet; phase-2's own bar).
- [ ] **Material-dispute rate < 20%** (currently ≥ 20%; phase-2's own bar).
- [ ] **Parked rate < 15%** of slices route to the human queue.
- [ ] **Gate honesty:** `gate_canary` runs the **real production gate stages**
      (not `[]`), in CI, with **zero false-passes** on the labeled mutant set;
      integrity-discrimination test in CI.
- [ ] **Survivability:** watchdog bounds every agent call; a hung/stuck slice is
      reaped and routed, never hangs the run; a crashed run **resumes** from
      durable state.
- [ ] **Demonstrated lift:** a repeated measurement shows Conveyor beats
      bare-agent baseline on **completion-under-autonomy and/or defects-caught**
      (not necessarily pass@1).

---

## 5. The milestone roadmap

Two tracks. **Track A (M0–M6): serial to the bar.** **Track B (M7+): parallel.**
Within Track A, "wire existing" milestones are cheap (the code exists); treat
them as the spine.

### TRACK A — Serial, fully autonomous, to the exit bar

#### M0 — Honesty cleanup _(days; pure de-risking)_

Make our own dashboard trustworthy before we steer by it.

- Fix `mix conveyor.eval.lift` crash (usage.json/seed.json glob collision in
  `lift_duel.ex`).
- Make `conveyor.gate_canary` pass the **real** production gate stages (today it
  passes `[]` — an empty gate that approves everything) and run it as a **CI
  guardrail.**
- Reconcile contradictory docs: `00-FIRST-LIGHT-HANDOFF.md` (stale — lists
  shipped closers as "next") and `RAW-LEVERAGE-PROGRAM-PLAN.md` ("ALL ITEMS
  IMPLEMENTED" — they're unwired islands). Point both at this ROADMAP.
- **Exit:** green eval-lift in CI; gate_canary proves discrimination in CI; no
  doc claims a capability that has zero callers.

#### M1 — Join the seam: real agent through the production loop _(the keystone)_

The single highest-leverage action in the whole codebase.

- Run the real **Codex adapter** through `PlanRunner`/`SerialDriver` — all 6
  stations + 4 gate stages + real `Finalizer` — on the existing Beads-Insight
  plan (today this exact path has never run with a real agent).
- Record it as a **cassette** and add it as a committed CI test of
  `mix conveyor.run` (replaces the `Process.put` stub).
- **Exit:** one real-agent slice goes
  context→implement→evidence→gate→accept→commit through the _production_ loop,
  reproducibly, in CI.

#### M2 — Close the loop unattended on ONE slice: wire the dormant closers _(wire existing)_

Stop halting on first failure.

- Wire **`AttemptLoop`/`ReworkSynthesizer`** into `SerialDriver.run_one!`: a
  non-accepted slice triggers automatic, budgeted rework instead of
  park-and-halt.
- Wire **ADR-24 `MidflightCheck`** (conductor-mediated read-only "which AC am I
  failing / did I touch a locked path") to raise pass@1.
- Wire **ADR-26 `AmendmentRouter`** so a _contract-defect_ failure proposes an
  amendment (separation-of-duties preserved: implementer can't relax its own
  contract).
- Add a **watchdog/timeout** around `codex.ex` `System.cmd` (today unbounded — a
  hung Codex hangs the run forever).
- **Exit:** one slice can fail→rework→pass, or fail→escalate/park, **without
  halting**, with a bounded attempt budget.

#### M3 — Close the loop unattended on a SMALL multi-slice plan (3–8 slices)

- **Skip-and-continue / park-and-proceed** over the dependency subgraph: a
  parked slice skips its dependents but lets independent slices proceed (today
  abstain/park/fail all `:halt`).
- **Durable resumability:** persist work-graph progress so a crashed run resumes
  (replace in-memory `Enum.reduce_while`).
- **Per-slice workspace isolation seam:** branch/worktree per slice +
  diff-policy-enforced commit (replaces blind `git add -A && commit`). _This is
  the parallel-ready seam (principle 4) AND a real-repo safety fix._
- **Exit:** a real 3–8 slice plan completes fully unattended with real Codex,
  surviving at least one induced slice failure, N consecutive runs.

#### M4 — De-neuter the gate (activate the judge that's already built) _(wire existing, not build)_

Now that the loop closes, make the verdict trustworthy. **Wiring, not new
verifier.**

- Wire the dormant **IntegritySentinel** producers (8 of 10 probes have none)
  and default the production loop to the **hermetic Docker backend** so
  hermeticity is actually asserted.
- **Agent isolation becomes a HARD requirement here (see D1, §7).** Wire the
  dormant `DockerRunner` + `ToolchainRunner` hermetic backend + `Sandbox.Reaper`
  so the agent **and** the gate run in **one pinned hermetic image** — this is
  precisely what lets the hermeticity probe fire and makes the §4
  zero-false-pass bar achievable (it cannot be met on the host). That same image
  becomes the per-worker container at M8, so this spend pays forward to parallel.
  _(File the Docker-wiring task under M4 when M4 is cut.)_
- Write **`corpus_pass_rate`** and **`replay_divergence`** from production
  stations so `TrustScore` stops defaulting unmeasured→trustworthy.
- Make **abstain fire on real signals**, not just the two recognized negatives.
- Replace hardcoded `replay_fidelity: "matched"` with a real
  recorded-vs-replayed compare.
- Re-validate honesty: real `gate_canary` + integrity-discrimination in CI (from
  M0).
- **Exit:** the live gate measurably discriminates (zero false-pass on mutants);
  abstain fires for real on low-confidence passes; first-pass-gate-success and
  material-dispute-rate measured against the §4 bar.

#### M5 — Long-horizon autonomy & drift defense _(the real dragon)_

Make an overnight unattended run trustworthy.

- **Drift / no-progress detection:** heartbeat, "N slices no forward progress,"
  agent looping on the same failing test.
- **Convergence Sentinel** (anti-thrash) + **Repeat-Offender Escalation**
  (re-cut the slice / park after K attempts).
- **Enforce `EmergencyStop`** + activate **`BudgetReservations`** (runaway
  kill-switch; reserve-before-effect).
- **Retention/GC sweeper** (ADR-10) so long runs don't accumulate unbounded
  blobs/evidence.
- Wire the **morning digest + parked-queue triage** (`ParkedQueueLive` exists —
  connect it).
- **Exit:** a **medium plan (15–40 slices)** completes unattended overnight;
  stuck/runaway conditions are detected and handled, not hung.

#### M6 — Autonomous decomposition (close the front of the loop; the bridge to parallel)

This is where "hand over a large plan" becomes real — and it produces the
parallel-ready substrate. Can be developed concurrently with M4/M5 (separate
subsystem).

- Wire **`PlanFoundry`/`CodexDrafter`** into `mix conveyor.author "intent"` →
  `conveyor.plan@1` → run.
- Replace the **content-blind `Decomposer` stub** with a real one that derives
  epics/slices/atomicity from plan content.
- **Compute real `work_dependencies`** from declared interface bindings
  (`SliceDependency` + `InterfaceGraph`) instead of the linear pairwise chain.
- Fire the **Interrogator** (ADR-27) on genuine ambiguity
  (`:needs_clarification`) instead of guessing.
- **Validate the graph as if parallel** (principle 4): build each slice against
  its deps' frozen interface stubs, even while executing serially.
- **Exit:** a prose plan → autonomous decomposition → unattended serial build to
  green; the dep-graph is _computed_ and _stub-validated_, so it's trustworthy
  as a parallel substrate.

**→ Track A exit gate = §4 bar fully met. Only then does Track B begin.**

### TRACK B — Parallel (the dial from 1 → N)

#### M7 — Within-slice speculative parallelism _(wire existing: ADR-25)_

Lowest-risk parallelism first: race N candidate implementations for one slice,
gate + `TrustScore` pick the winner. `RaceConductor` is already built and
unwired; cost-governed.

#### M8 — Cross-slice fleet

Dispatcher + WorkerPool + MergeQueue + Governor; **activate the dormant
Oban/Conductor substrate** (first-ever `Oban.insert`; turn on Conductor
children + Cron/Pruner plugins); container isolation per agent; branch-per-slice
→ integration gate on `dev` → phase-gate to `main`. Then BEAM distribution for
horizontal scale.

---

## 6. Deferred / parked backlog (explicitly NOT on the critical path)

Real ideas, deliberately parked with rationale — revisit after the §4 bar, or
when a milestone pulls one in:

- **Verifier-as-product / Findings-to-Fix** (the strategic moat — point the gate
  at _external_ repos). High value, but premature until our own loop closes.
  _Park._
- **Scar Ledger / FailureMemory + pgvector recall** (institutional memory; the
  "compounding flywheel"). Pull in once we have enough real runs to learn from
  (post-M5). _Park._
- **Divergence Bisector** (git-bisect over the event log via
  `ReplayDiagnostics`). Depends on a real replay corpus. _Park._
- **Honesty/calibration eval (Rung 3)** + **adversarial agent /
  cheat-resistance + self- growing corpus (Rung 2)**. Fold into M4's
  gate-honesty validation. _Partially pulled into M4._
- **Multi-archetype + brownfield onboarding** (today: single greenfield
  pure-logic Python archetype; `ToolchainRunner` hardcodes pytest). Needed
  before "any plan," not before "a plan." _Park until post-bar._
- **CredentialPool / CAAM, multi-model routing, economic governor reporting.**
  Parallel-era concerns. _Park to Track B._
- **DSPy/GEPA prompt-template optimization.** Needs the eval flywheel turning
  first. _Park._

---

## 7. Risks & open questions

- **R1 — Zero demonstrated lift so far.** The only real measurement is pass@1
  lift = 0.0. Mitigation: M0 fixes the eval; M4/M5 reframe the metric to
  completion-under-autonomy + defects-caught. _If, after M5, Conveyor still
  shows no lift over bare-agent on any axis, that is a stop-and-rethink signal._
- **R2 — Two divergent execution paths** (production `SerialDriver` vs eval
  `GoldenThread`). M1 collapses them; until then, every "it works" claim must
  say _which_ path.
- **R3 — Real-repo safety.** The loop commits in-place with `git add -A`. M3's
  per-slice isolation is a prerequisite for running against anything but a
  sterile sample repo.
- **R4 — Decomposition quality is unproven** and is the load-bearing artifact
  for the whole dream. M6 + principle-4 stub-validation are the guardrails;
  expect iteration here.
- **D1 — Agent isolation: DECIDED (staged, not binary).** "Isolation" bundles
  five distinct jobs; only one is parallel-only, so Docker is gated on the
  _autonomy/duration_ dials, **not** width:
  1. **Blast-radius containment** (your host, _other_ repos, creds) — serial;
     importance scales with _unattendedness_ → needed by **M5**.
  2. **Hermeticity / reproducibility** (gate honesty; the IntegritySentinel
     hermeticity probe is `not_assessed` without it) — **makes Docker a HARD
     requirement at M4**; the zero-false-pass exit bar cannot be met on the host.
  3. **Clean-slate teardown** (trustworthy repeats + clean-env gate re-verify) —
     M3–M4.
  4. **Concurrency isolation** (N agents not colliding) — **parallel-only → M8.**
  5. **Network egress control** — M5.

  **Plan:** keep host `codex --sandbox workspace-write` through **M0–M2** (don't
  slow the keystone; Docker Desktop's VM layer would drag the inner loop). Make
  Docker a hard requirement at **M4** (hermeticity) and **M5** (blast-radius), by
  _wiring the existing_ `DockerRunner` + `ToolchainRunner` hermetic backend +
  `Sandbox.Reaper`. **Architecture rule: one pinned image shared by the agent AND
  the gate** — else "passes in agent, fails in gate" returns; that image is
  reused as the per-worker container at M8 (pays forward, not throwaway).
  **Open sub-decision that sets urgency — what repos do unattended runs target?**
  Sterile/disposable sample repos → host sandbox tolerable into M5; real/valuable
  repos (e.g. self-hosting) → blast-radius (#1) pulls Docker earlier. _Decide
  before the first unattended real-repo run._
- **D2 — `br` tracking: DONE.** M0–M3 filed under epic
  `software-factory-ai-jwxp` (ROADMAP Track A) with the milestone chain
  M0←M1←M2←M3; existing `dr1m` issues (`.9` AttemptLoop, `.10` docs, `.12` eval
  venv, `.4.1` AmendmentRouter) linked, not duplicated. M4–M8 filed as they near.

---

## 8. Mapping to prior planning

- **Supersedes** the abstract "Phase 0–8" list in `BRAINSTORM.md` §6 with
  reality-grounded milestones. Rough map: BRAINSTORM Phase 1 (tracer) ≈
  _done-ish but seam-severed_ → M1; Phase 2 (decomposition) → M6; Phase 3
  (parallel fleet) → M8; Phase 4 (verification pyramid) → mostly _built, M4
  wires it_; Phase 5 (self-healing) → M2/M3/M5; Phase 6 (governor/observability)
  → M5; Phase 7 (learning) → parked §6; Phase 8 (parallelism) → M7/M8.
- **ADRs 01–23** are largely realized in the live path. **ADRs 24–27** are the
  dormant closers this roadmap _wires_ (M2 wires 24/26; M6 wires 27; M7 wires
  25).
- The **raw-leverage thesis** ("activate the dormant verifier, aim it at
  throughput") is the spine of Track A — M2/M4/M5 are that thesis made concrete.

---

_Last updated: 2026-06-21, from a 16-agent evidence audit of the live execution
path._
