# M4 — Activate + Finish the Gate: Comprehensive Implementation Plan

> **Status:** PLAN — not started; revised to be self-contained for external review (Background A & B added), then patched after an adversarial review pass. **Post-review patch covers:** the one real blocker (an *advisory* canary's `canary_false_negative` cannot reach the critical stop-the-line branch — it is gated behind `passed? == false` — so E9's reachability proof needed a new `finalizer.ex` critical-finding precedence edit, scoped to exclude `stale_canary` so it never force-parks the reference); the stale "canonical" ownership/atomic-commit contradictions (D3 is an M4.7 prerequisite, NOT part of the `{D4 + C1}` atomic commit; replay/corpus owned by **B** not A/C; integrity flip owned by **D4** only); the §6 row-3 keystone clarification; the B1 rework/replay-baseline refinement (record on the final accepted attempt; add a real cross-run `:diverged` falsifier); the A2 `pytest` path bug; and the agent-runs-on-host trust-boundary honesty note. *(The automated pass also flagged a second "blocker" — rework recovery parking under the replay producer — which a code-grounded re-check downgraded to a narrow edge case; see the revised B1 risk bullets.)*
> **Date:** 2026-06-23 (self-contained revision + post-review patch; original plan dated 2026-06-22).
> **Source:** an 8-reader code map of the live tree (8 designer sub-streams, each of which Read every named module/line and verified the seed facts before designing) + Robert's 5 ratified decisions for this session.
> **Relationship to ROADMAP.md:** this is the execution plan for **ROADMAP.md → M4 — "Activate + finish the gate"** (the heaviest Track-A milestone: net-new verifier completion, not mere wiring). ROADMAP M4's one-line exit — *"the live gate measurably discriminates (zero false-pass on mutants); abstain fires for real; first-pass-gate-success + dispute-rate measured"* — is decomposed here into 8 sub-streams, ~50 green-committable slices, and an explicit ordered master sequence. M4 satisfies a **subset** of the ROADMAP §4 serial bar (gate honesty + abstain-fires + hermeticity + measured first-pass/dispute/parked); the joined-seam / decomposition-in-loop / unattended-medium-plan items remain for M1/M5/M6 and are explicitly out of scope here.

---

## 1. Title & status banner

This document is the single source of truth for executing M4. It is written to be executed **top to bottom by a brand-new agent with zero prior context**. Every sub-stream section was authored by a designer who Read the real code at the named lines; the per-slice detail (files, functions, exact CURRENT→TARGET edits, discrimination tests, green criteria, br issues, risks) is preserved **verbatim** below in Section 8 — that is the execution body. Sections 1–7 and 9–14 are the connective tissue and master sequencing.

> **For a reader with zero prior knowledge of this codebase (an external reviewer, or another model such as GPT Pro asked to critique this plan):** read **Background A** and **Background B** immediately below *first*. They were added to make this document fully self-contained. **Background A** explains what Conveyor (this project) is, how it works end-to-end, what makes it compelling, and why M4 is the load-bearing milestone. **Background B** explains Codex — the autonomous coding agent Conveyor wraps and whose output the gate exists to verify — and the exact mechanics of how the two integrate. Everything in Sections 2–14 (and the dense per-slice detail in Section 8) assumes the vocabulary those two sections establish; a reviewer who skips them will not be able to tell a real design flaw from an unfamiliar term.

---

## Background A — What Conveyor is and how it works (zero-context primer)

> This section is orientation for a reader who has never seen this codebase. It is descriptive (what exists today), not part of the M4 work. Where it states a number or behavior the M4 plan changes, it says so.

### A.1 — What Conveyor is, in one paragraph

**Conveyor** (this repository, internally `software-factory-ai`) is an **AI-first "software factory" built on the BEAM** (the Erlang/Elixir/OTP runtime). You hand it a high-level **plan**; it compiles that plan into a dependency-ordered work-graph of **contract-bearing slices** (each slice = one unit of work with an immutable, machine-checkable acceptance contract); then it drives an autonomous coding agent (Codex by default — see Background B) to implement each slice inside an isolated workspace, and runs every result through a **deterministic verification gate** that decides — with *no human watching* — whether the work is correct, safe, and good enough to merge. The human's job shrinks to reviewing a morning digest and a small "needs-judgment" queue of items the gate honestly could not adjudicate. Conveyor is event-sourced and content-addressed: every run is recorded, replayable deterministically, and becomes permanent machine-checkable evidence. It is a solo-developer project; its current target is **serial, single-agent, fully-autonomous** completion of one class of task before any cross-slice parallelism is added.

### A.2 — The core thesis (why Conveyor exists)

Conveyor's bet is that the field's **hardest unsolved problem is trustworthy autonomous verification when no human is watching** — and that Conveyor is "accidentally sitting on this problem with most of the substrate already built and dormant." Coding agents have become good at *producing plausible diffs*; what nobody has solved is an automatic judge that can look at an agent's output and say "this is genuinely correct and safe — merge it" or, crucially, "**I cannot tell — escalate this one**," and be *calibrated* about which is which. Tests and linters catch *known* failure modes; they do not adjudicate *unspecified* intent. Conveyor's wager is that a deterministic, evidence-backed, **ternary** gate (pass / **abstain** / fail) — fed by real measurement rather than fabricated signals — is the missing piece that turns a stochastic coding agent into an autonomous system you can leave running.

The phrase the plan quotes as the north star is **"trustworthy autonomous verification when no human is watching."** M4 is the milestone that makes that real: today the gate is fully wired but **vacuous** — it launders unmeasured trust signals into passing tokens, so a clean run always scores ~0.925 and always auto-accepts, and *abstain can never fire*. Until M4 lands, "green" from the factory is unverified. (Section 3 of this document is the full diagnosis.)

### A.3 — What makes Conveyor special / compelling

- **Verification lift, not raw agent capability, is the product.** The differentiator vs. running a bare agent (Codex, Claude Code, etc. on their own) is *proof* that the code is actually correct — and concrete evidence of **defects caught that a bare agent would have merged**. Conveyor measures this directly (its "lift duel" runs the same task through the full Conveyor loop and through a naive one-shot prompt, both judged by the *identical* gate; see Background B.7).
- **Calibrated abstention (the 90/10 problem).** Agent reliability improves far slower than raw capability; a 90%-accurate agent that fails *unpredictably* on the other 10% is "a useful assistant but an unacceptable autonomous system." Conveyor's gate is built to **abstain — park the slice for a human — instead of confidently auto-merging a result it cannot vouch for.** Abstention being *honest* (firing on real missing signals) is exactly what M4 delivers.
- **A hard determinism boundary.** Agents own *drafting and implementation* (inherently stochastic); the **Conductor** (the BEAM/OTP core) owns *verdicts, policy, and evidence* (deterministic, pure functions, replayable). This split is load-bearing: the gate's judgment is byte-reproducible from recorded evidence, even though the code it judges came from a stochastic agent.
- **Everything is recorded (event-sourced + content-addressed).** Every decision, artifact, and run trace is immutable and hashed. This buys reproducible AI review, time-travel debugging, deterministic replay for CI at $0, and an eval dataset the factory learns from.
- **Built on the BEAM.** Long-horizon, crash-resilient, resumable orchestration is OTP's home turf — structurally where Python/cloud incumbents are weakest for hours-to-days unattended runs.
- **Cost-per-verified-outcome as a first-class metric.** Conveyor meters tokens and a list-price-equivalent cost *per verified acceptance criterion*, not just raw spend — leverage governance for a solo operator.

### A.4 — How it works: a slice's journey end-to-end

A unit of work is a **slice**. It flows through a **pure-function planning compiler**, then an **execution pipeline of "stations,"** then the **gate**, then the **finalizer**:

1. **Planning (Conductor-owned, deterministic).** A plan is audited (`StructuralAudit`), decomposed into candidate slice-graphs (`Decomposer`), one decomposition is selected by strict domination (`DecompositionSelection`; ties require a human decision), analyzed (`GraphAnalyses`, `InterfaceGraph`), and lowered to a `conveyor.work_graph@2` IR (`WorkGraphLowering`). Every pass is a pure function with content-addressed caching.
2. **RunSpec assembly.** `RunSpecAssembler` freezes an immutable, content-addressed **`RunSpec`** for the slice attempt: base commit, the **station plan**, the contract/contract-lock, policy, prompt, and all digests. This is the reproducible input object.
3. **Stations (the executable pipeline; Oban jobs, idempotent).** In order: **context_scout** (read-only code-context gathering), **baseline_health** (run the project's regression suite on a clean base checkout), **acceptance_calibration** (run the slice's *locked acceptance tests* on the base commit — they must be **red on base**, proving they actually assert the new behavior), **implement** (launch the agent — Codex — to produce a `PatchSet` + an `AgentSession`), **verify** (re-run the locked verification commands via the `ToolchainRunner`, produce a structured `verification_result` + integrity observations), **record_evidence** (independently map acceptance criteria → results, scan for secrets, write a content-addressed `evidence.json` packet + `Artifact` rows).
4. **The gate.** `Gate.run!` runs **14 stages** (pure functions over a context map) and produces a `GateResult`. The gate *passes* only if every **required** stage passes.
5. **The finalizer.** `Finalizer.finalize!` turns a passed gate + the trust evidence into a **ternary verdict** and persists the outcome (and, on a real accept, mints provenance — see A.8).

### A.5 — The verification gate in detail (the thing M4 activates)

The gate is a list-driven pipeline of **14 stages**, each a `StageSpec{key, module, required?}` (canonical numbering from `droid-wiki/systems/gate.md`):

> 1. workspace_integrity · 2. diff_scope · 3. observed_risk · 4. policy_compliance · 5. secret_safety · 6. build_install · 7. test_execution · 8. acceptance_mapping · 9. contract_lock · 10. code_quality_delta · 11. run_check · 12. provenance_attestation · 13. reviewer_aggregation · 14. canary_freshness

- A stage returns `:passed | :failed | :skipped` plus `findings` (each with a **category** / `rule_key`, severity, message). A **required** stage that fails (or reads a missing required input → fails *closed*) makes the whole gate `passed? == false`. A non-required (**advisory**) stage records findings but never blocks.
- The gate's outcome lives on `RunAttempt.outcome` (`:accepted | :needs_rework | :rejected | :policy_blocked | :abstained`) and `Slice.state` (`:gated | :parked | :needs_rework | :policy_blocked | :failed | …`). (M4 also adds a first-class `verdict` column to `GateResult` so this is queryable directly.)
- **The state today vs. at M4 exit:** only **4** stages run live today (diff_scope, secret_safety, test_execution, contract_lock). M4 brings the cheap deterministic stages live (workspace_integrity, observed_risk, policy_compliance, acceptance_mapping, run_check) for **9 required-live**, with provenance_attestation/canary_freshness/build_install/code_quality_delta/reviewer_aggregation **advisory** (some with a gated, deferred "required" flip). M4 also makes the two long-dead Finalizer branches — `:policy_blocked` and the critical "stop-the-line" rejection — actually *reachable* from real wired stages.

### A.6 — TrustScore + TrustEvidence: the calibrated-confidence layer (ADR-23)

A *passed* gate is necessary but not sufficient for auto-merge. The **TrustScore** (`lib/conveyor/gate/trust_score.ex`) fuses **five evidence signals** into a band:

| signal | weight | good token → 1.0 | "soft"/0.5 | bad token → 0.0 |
|---|---|---|---|---|
| **integrity** (IntegritySentinel verdict) | 0.30 | `"trustworthy"` | `"suspect"` / `"not_assessed"` | `"untrustworthy"` |
| **calibration** (acceptance test-pack) | 0.20 | `:valid` | `:not_assessed` | `:invalid` |
| **baseline** (baseline-health) | 0.20 | `:green` | `:unknown` | `:red` |
| **replay** (recorded-vs-replayed divergence) | 0.15 | `:none` | `:unknown` | `:diverged` |
| **corpus** (historical pass-rate, boost-only) | 0.15 | float | `nil` → 0.5 (cold start) | low float |

- **Threshold:** `auto_accept: 0.9`. **Auto-accept requires BOTH** the hard gate `trustworthy?/1` (integrity `"trustworthy"` ∧ calibration `:valid` ∧ baseline `:green` ∧ replay `:none` — corpus deliberately excluded so cold-start never blocks) **AND** weighted `score ≥ 0.9`. Otherwise the band is **`:abstain`**.
- **`TrustEvidence`** (`trust_evidence.ex`) assembles the evidence map from a slice's raw `output` via `from_run_output/1`. **This is where the vacuity lives today:** it *launders* every absent/unmeasured signal to its passing token (`calibration(_) → :valid`, `baseline(_) → :green`, `integrity(_) → "trustworthy"`, `replay(_) → :none`), so a run with *no real measurement at all* assembles as fully-good evidence and scores `0.30+0.20+0.20+0.15+0.15·0.5 = 0.925 ≥ 0.9` → auto-accept. **Making `from_run_output` stop laundering — and flipping each signal "fail-closed" only once its real producer exists and the known-good reference still auto-accepts — is the spine of M4.**

### A.7 — IntegritySentinel: the anti-vacuity oracle (the integrity signal's producer)

`IntegritySentinel` (`lib/conveyor/verification/integrity_sentinel.ex`) is a deterministic oracle that folds **10 probes** into the integrity verdict (`trustworthy | suspect | not_assessed | untrustworthy`). Its purpose is to detect tests that *pass vacuously* — suites that run but don't actually exercise the code, or that pass regardless of the change. The 10 probes:

> `base_calibration` · `repeatability` · `hidden_dependency` · `mount_boundary` · `mapping` · `required_artifacts` · `falsifier_survival` · `falsifier_preservation` · `source_mutation` · `hermeticity`

Today **only 2 of 10** ever receive an observation (`source_mutation`, `hermeticity`), and `hermeticity` is observed only under a Docker backend; on the default `:local` backend the verdict is honestly `not_assessed` — which the laundering then maps to `"trustworthy"`, scoring 1.0. M4 builds real producers for the dormant probes and admits the cheap, high-confidence ones to the live required set (this is sub-stream C). "**Hermeticity**" specifically means a 6-control observation (`network/clock/rng/ordering/locale/shared_state`) only honestly measurable inside a `docker --network=none` container — the basis for M4's hermetic-gate work (sub-stream D).

### A.8 — The Genome (provenance + historical priors)

The **Genome** is Conveyor's institutional memory. When a slice passes the gate for real, `BackEdge.mint!` writes immutable **`CodeProvenanceEdge`** rows (`role: "verified_by_gate"`) linking the verified code symbols ↔ acceptance criteria ↔ patch digest ↔ gate result. This provenance graph (a) is the audit trail for "what verified this code and why," and (b) eventually supplies the **`corpus_pass_rate`** historical prior to the TrustScore. (M4 also fixes a real correctness bug here — duplicate edges minted on every re-finalization because the edge hash included a per-finalization nonce; sub-stream G.)

### A.9 — The honesty machinery: the eval harness and `scorecard --gate`

Conveyor *gates its own CI on whether its gate is honest.* The key pieces:

- **MutantGauntlet** (`lib/conveyor/eval/mutant_gauntlet.ex`): applies a corpus of known-defect "mutant" patches to a sample project and asserts the gate **catches each one** — emitting a `false_pass_rate` metric (blocking, target **0**). Today it only exercises *behavioral* mutants (the `test_execution` stage); M4 extends it to the *static-stage* mutants (policy/contract/run_check) and demands each be caught **for the right reason** (`caught_by_expected?`), so a stage that rejects by accident doesn't count as a real catch.
- **SentinelTournament**: plants one vacuity per IntegritySentinel probe and measures `sentinel_evasion_rate` (target 0) and `sentinel_probe_coverage` (target 1).
- **Scorecard / `mix conveyor.eval.scorecard --gate`**: aggregates every eval suite's metrics; exits non-zero (CI red) if any *blocking* metric is off-target. This is the **hard, $0, deterministic CI gate** that the M4 exit criteria hang on.
- **The canary corpus & sample projects:** `samples/tasks_service` (the gauntlet's primary, with a `mutants.json`), `samples/beads_insight` (7 greenfield slices, with reference patches), `samples/gx` (per-slice reference patches, no mutants yet). The "**known-good reference**" — the reference patches run through the gate — **must auto-accept at every single M4 commit** (the `loop_integrity` invariant). The whole incremental-fail-closed discipline exists to never park the reference.

### A.10 — Cassettes & deterministic replay

Every real agent run is recorded into a **cassette** (a sealed, redacted, content-addressed event stream + the workspace diff it produced). A `ReplayEngine` can then re-drive a recorded run deterministically (`:full` / `:hybrid` modes) — which is what lets CI re-verify a real-agent run for **$0** and lets the gate compute a real **replay-divergence** signal (recorded digest vs. replayed digest). M4 replaces a hardcoded `replay_fidelity = "matched"` with a real per-slice divergence producer (sub-stream B).

### A.11 — Tech stack

Elixir (`~> 1.20`) on OTP; **Ash** (`~> 3.29`) for resource/domain modeling (45+ resources: Project, Plan, Slice, RunAttempt, RunSpec, GateResult, Artifact, AgentSession, CodeProvenanceEdge, …) with `ash_state_machine` for lifecycles; **Ecto + AshPostgres** over **Postgres**; **Oban** for durable, transactional jobs (queues: `default`, `conductor`, `gate`, `maintenance`); **Phoenix + LiveView** for a *read-only* dashboard (the web layer never creates authority). Verification runs in a hermetic **Docker** runner (`docker --network=none`) or a local venv fallback. Conductor-side code is pure (no I/O, clock, or RNG in the gate/scorer) so verdicts are replayable. CI runs everything under `Ecto.Adapters.SQL.Sandbox` (ephemeral DB), which is why one M4 data-integrity fix (sub-stream G2) is *latent* in CI.

### A.12 — Milestones, and where M4 sits

Track A is "get serial, single-agent autonomy fully working, to the bar." Rough sequence (status as of this plan):

- **M0 — Honesty cleanup** ✅ done.
- **M1 — Join the seam: real agent through the production loop** ✅ done (the keystone — proved *wiring* stability, not agent reliability).
- **M2 — Close the loop on one slice** (rework-on-fail, mid-flight self-check, watchdog) — in progress.
- **M3 — Unattended on a small (3–8 slice) plan** — planned.
- **M4 — Activate + finish the gate** ← **this document.** The heaviest Track-A milestone: real trust producers, real abstain, a hermetic gate, all 14 stages live with the dead failure branches reachable, the MutantGauntlet extended, two data-integrity fixes — all under *incremental fail-closed* discipline. Exit (a subset of the §4 serial bar): zero false-pass on the full mutant corpus in CI; abstain proven to fire; hermeticity-absent abstains rather than false-passes; first-pass-gate-success / dispute-rate / parked-rate **measured** (not gated — see B.9).
- **M5 — Autonomous decomposition**, **M6 — Long-horizon autonomy + medium (15–40 slice) plan** — planned. (Cross-slice parallelism is a later track, deliberately deferred until serial clears the bar.)

### A.13 — Vocabulary a reviewer needs (used everywhere below)

- **Fail-open vs. fail-closed.** A signal "fails *open*" if, when unmeasured, it defaults to the *passing* token (the current vacuity). It "fails *closed*" if it defaults to the *abstaining/blocking* token (the M4 target). **Incremental fail-closed** = flip a signal fail-closed *only* in the same change that lands its real producer, *and* only after confirming the known-good reference still auto-accepts.
- **`not_assessed` (non-blocking) vs. `missing` (blocking)** — the keystone taxonomy (Section 6). `not_assessed` = a *positive, recorded* "genuinely cannot be measured on this backend" declaration (e.g. hermeticity with no Docker) → contributes 0.5, never hard-blocks. `missing` = "a producer that *should* have run is absent/empty" → fail-closed → abstain. `from_run_output` must never default an *expected* signal to its passing token.
- **Abstain / park.** A *passed* gate that the TrustScore cannot vouch for → `RunAttempt.outcome = :abstained`, `Slice.state = :parked`, **no auto-merge, no provenance minted** — routed to a human queue. This is the calibrated "I don't know."
- **"Looks-wired-but-vacuous."** The recurring failure mode this whole milestone fights: code that *appears* to do honest verification but produces no real signal (e.g. a canary harness whose patch carries no `changed_files`, so every static stage sees an empty diff and "passes"). The antidote is the **discrimination test**: every signal must be proven in *both* directions — a BROKEN input must abstain/reject *with the exact expected finding category*, and a GOOD input must accept. A test that only checks the green direction is disallowed.
- **Greenfield vs. brownfield; width-1.** Conveyor's current bar is measured on *greenfield, pure-logic, golden-oracle* tasks (the easiest class). The loop is **width-1** (strictly serial, one slice at a time) on purpose; parallelism is a later concern.

---

## Background B — What Codex is, and how Conveyor uses it (zero-context primer)

> Conveyor is agent-agnostic in principle (it has several adapters), but **Codex is the default and the agent the M4 plan validates against** ("a bounded live-Codex pass"). A reviewer needs to understand Codex because *the entire gate exists to verify a stochastic Codex diff*, and because the plan's value claim ("lift vs. a bare agent") and its live-measurement step are both defined relative to Codex.

### B.1 — What Codex is

**Codex** is OpenAI's autonomous software-engineering agent. (The name has lineage: "Codex" was originally OpenAI's 2021 code-generation *model* that powered early GitHub Copilot; OpenAI revived the name in 2025 for an *agentic coding product* — a fundamentally different thing: not a single completion model but an agent that operates a real development environment.) In its modern form Codex is given a task in natural language and **autonomously drives an iterative loop**: it reads the repository, plans, edits files, runs commands and tests in a sandbox, observes the results, and keeps going until it believes the task is done — then it produces a diff (and, in its hosted form, a pull request) with citations to the terminal logs and test output that justify its changes.

It ships in two main forms:
- **Codex CLI** — an open-source terminal agent you run locally; it edits files and runs commands on your machine within a configurable sandbox. It has a non-interactive/headless mode (`codex exec`) suitable for automation, and can emit structured JSON/JSONL output. **This is the form Conveyor drives.**
- **Cloud Codex** — a hosted agent inside ChatGPT that runs each task in its own cloud sandbox, can work on many tasks in parallel, and returns PRs.

Both are powered by SWE-tuned models in the Codex family (e.g. `codex-1`, a software-engineering-optimized variant of OpenAI's reasoning models, and successor `*-codex` models). Access is bundled into ChatGPT subscriptions (Plus / **Pro at $200/mo** / Team / Enterprise) and is also available via API. *(Exact model names and tier details evolve; the repo-grounded integration facts below are the authoritative part of this section.)*

### B.2 — How Codex works (the agentic loop)

1. **Context-build.** Codex explores the repo (reads files, greps, inspects structure) to ground itself in the actual code rather than hallucinating an API.
2. **Plan + act.** It proposes and applies edits, then runs build/test/lint commands inside its sandbox.
3. **Observe + iterate.** It reads command output and test results and revises — a test-driven loop, not a single completion. This iteration is the source of its leverage *and* its non-determinism.
4. **Produce a justified diff.** It returns the workspace changes plus a transcript citing the commands/logs that support the result.

Its **sandbox modes** govern what it may touch (e.g. read-only, *workspace-write*, or full access) and whether it has network — the safety surface that lets it run commands autonomously.

### B.3 — What makes Codex special / compelling

- **End-to-end autonomy on real repos** (not just snippet completion): it edits, runs, tests, and iterates by itself.
- **Test-driven self-correction:** it uses real command/test feedback to converge, which is why it can finish non-trivial tasks unattended.
- **Sandboxed execution:** running commands inside a permissioned sandbox makes "let an agent run your test suite" tractable.
- **Transparency / citations:** it surfaces the logs and test results behind its diff, which is exactly the kind of *evidence* a downstream verifier can record.
- **Parallel cloud tasks** (hosted form) and **subscription economics:** under a flat-rate ChatGPT Pro plan, the *marginal* cost of an additional run is effectively $0, which changes the economics of running many verification passes.

### B.4 — Why Codex is the *reason the gate exists* (the design tension a reviewer must hold)

Codex is powerful but **stochastic and not perfectly reliable** — the "90/10 problem": it succeeds most of the time but fails *unpredictably* on a minority of tasks, and a confidently-wrong diff is indistinguishable, on its face, from a correct one. That is precisely the gap Conveyor's gate is built to close. So when reviewing this plan, hold this frame: **Codex produces; the gate adjudicates; the two must be on opposite sides of a determinism boundary.** Codex's diff is the *untrusted input*; the gate's job is to be *unfoolable* by a plausible-but-wrong Codex diff — which is impossible if the gate launders unmeasured signals into "trustworthy" (today's bug, M4's fix).

### B.5 — Exactly how Conveyor invokes Codex (repo-grounded)

Conveyor uses a **pluggable adapter** pattern. `Conveyor.AgentRunner` is a behaviour (`run/4`, `cancel/2`, `capabilities/0`); the **implement** station selects an adapter module and calls it. The Codex adapter (`lib/conveyor/agent_runner/codex.ex`) drives the **Codex CLI as a host subprocess** — *not* in a container:

```
codex exec --cd <workspace> --sandbox workspace-write --json --ephemeral \
  --skip-git-repo-check [-m <model>] [-c model_reasoning_effort="<level>"] "<prompt>"
```

Key, somewhat non-obvious mechanics (all real, in the adapter):
- **It is the default adapter** — if no `--adapter` is given, Codex is assumed.
- **Run on the host via `System.cmd`, not Docker.** (Important: the Docker `--network=none` sandbox in Conveyor is for the *gate's verification rerun* — sub-stream D — **not** for the agent. Codex's own `--sandbox workspace-write` is Codex's internal write-permission, a separate thing.)
- **Headless stdin trap handled:** `codex exec` blocks forever reading stdin under `System.cmd`, so the adapter wraps it in `sh` and closes stdin (`</dev/null`).
- **Timeout watchdog** (default 900s) so a hung agent can't stall an unattended multi-hour run (returns exit 124 on timeout).
- **Injectable exec for determinism/$0:** the adapter takes an injectable `codex_exec` function; the default drives real `codex exec`, while tests inject canned JSONL + a patch so CI stays deterministic and free.
- **What it's given:** a versioned, content-hashed **`RunPrompt`** (the AgentBrief + acceptance criteria + cited `ContextPack` from the scout) and the **workspace** (repo path + base commit).
- **What it produces:** a **`PatchSet`** (the captured diff), an **`AgentSession`** row (tokens, cost estimate, status, a blob reference to the raw JSONL transcript), and the agent's final message — parsed out of Codex's `--json` JSONL stream.

### B.6 — The adapter abstraction (Codex is one of several)

| adapter | module | role |
|---|---|---|
| **codex** (default) | `AgentRunner.Codex` | real OpenAI Codex via the CLI |
| **reference_solution** | `AgentRunner.ReferenceSolution` | deterministic **$0** baseline: applies a fixed `.patch` *as if* an agent produced it (supports reverse-apply to model "the agent undid a mutation"); the "vanilla"/control arm and the CI stand-in |
| **pi** | `AgentRunner.Pi` | RPC interface to other agents (e.g. Claude Code) |
| **fake / mock_degraded** | test-only | canned / deliberately-malformed output for conformance tests |

This is why the plan can speak of "live Codex" vs. the deterministic reference arm interchangeably as *adapters behind the same `run/4` seam* — and why CI can be $0 and deterministic while live validation uses real Codex.

### B.7 — Cost & "lift vs. bare agent" (why the live step is bounded)

- **Token/cost accounting:** the adapter extracts `input + output + reasoning` tokens from Codex's JSONL `usage` and persists them on `AgentSession`, plus a **cost *estimate*** computed from list-price rates (≈ $1.25/1M input, $10/1M output) purely for telemetry — because under Robert's **$200/mo ChatGPT Pro subscription the marginal spend is ≈ $0** (flat-rate). The plan budgets the live pass in *tokens* (baseline ≈ **570k tokens/slice**; ~5 runs of 7-slice plans ≈ tens of millions of tokens) with a dev-phase not-to-exceed, and reports *both* a token total and a list-price-equivalent dollar figure.
- **Lift duel (`lib/conveyor/eval/lift_duel.ex`):** runs the *same* tasks through two arms — **treatment** (full Conveyor loop: rich brief + ContextPack, Codex) vs. **baseline** (naive one-shot prompt, same agent/adapter) — both judged by the **byte-identical gate** — and reports the Δ in pass@1, verified-acceptance-criteria, and **cost-per-verified-AC**. "Lift" = what Conveyor's contract+context+gate add over a bare agent. This is the operationalization of A.3's value claim.

### B.8 — Recording Codex runs → deterministic replay

Because Codex is stochastic, a live run is **recorded into a cassette** (sealed, redacted JSONL + patch digest, content-addressed). Thereafter the run can be **replayed deterministically** for CI at $0, and the gate can compute a real **replay-divergence** signal by comparing the recorded result digest to a re-derived one. This is how Conveyor gets the best of both worlds: real stochastic Codex output as *ground truth*, and deterministic, free re-verification in CI. (M1 — already done — proved exactly this seam end-to-end; M4 makes the divergence signal real rather than hardcoded.)

### B.9 — The determinism boundary (the single most important thing to grasp)

> **Agents own drafting and implementation (stochastic). The Conductor owns verdicts, policy, and evidence (deterministic, pure, replayable).**

This boundary is *why the M4 exit is split the way it is*, and a reviewer should sanity-check the plan against it:
- **CI-hard (deterministic, $0, blocking):** gate honesty (zero false-pass on the mutant corpus), abstain-fires-for-real, hermeticity-absent-abstains, the falsifier probe. These are provable without invoking Codex at all (the gauntlet runs *pytest*, the falsifier applies *patches*, the scorecard aggregates).
- **Live-measured (stochastic, REPORTED, never a gate):** first-pass-gate-success, dispute-rate, parked-rate, lift. The plan deliberately refuses to gate the milestone on these because they are a function of *Codex's* reliability, not Conveyor's correctness — and "coupling a milestone exit to a stochastic agent is a category error." If a reviewer's instinct is "why isn't first-pass ≥70% a hard gate?", *this* is the answer, and it is load-bearing.

### B.10 — What to keep in mind while reviewing this plan

The gate is the product; Codex is the (replaceable, stochastic) supplier of the diffs it judges. Every M4 design choice — stop laundering signals, flip fail-closed only with a real producer, prove discrimination in both directions, keep the known-good reference auto-accepting, gate CI on a deterministic mutant corpus but only *report* live-Codex numbers — follows from the relationship between these two systems: **make the deterministic judge genuinely unfoolable by a plausible-but-wrong stochastic agent, and prove it with evidence rather than assertion.**

---

## 2. Purpose & how to use this doc

**What M4 does, in one sentence:** the verification gate is fully wired end-to-end but **vacuous** — it launders unmeasured trust signals into passing tokens, so a clean run always scores ~0.925 and always auto-accepts, abstain can never fire, and only 4 of 14 gate stages are live. M4 makes the gate **honest**: real trust producers, real abstain, a hermetic (`docker --network=none`) verification backend, all 14 stages live with the dead failure branches reachable, the MutantGauntlet extended to the static stages, and the two data-integrity fixes — all under an **incremental fail-closed** discipline that keeps the known-good reference auto-accepting and the suite green at every commit.

**How to execute:**

1. **Read Section 5 (Glossary) and Section 6 (the taxonomy) first.** They define every term and the single load-bearing principle (`not_assessed`/non-blocking vs. fail-closed/abstain) that every sub-stream reuses.
2. **Follow Section 7 (Master Sequencing).** It interleaves the 8 sub-streams into one ordered list of sub-milestones (M4.1 … M4.N) that respects the dependency graph. Do them in that order.
3. **For each sub-milestone, open the corresponding sub-stream section in Section 8** and execute its slices exactly as written. Each slice names its files, functions, exact edits, discrimination tests, green criteria, and the br issues it closes.
4. **Obey the slice discipline at every commit** (below). This is non-negotiable and is what separates this plan from "looks-wired-but-vacuous" theater.

### The slice discipline (TDD, green-at-each-commit, incremental fail-closed)

Every slice follows the same shape:

> **wire one real producer → flip that signal fail-closed → discrimination test (broken signal → park/reject, good signal → accept) → re-tune (only if the reference dropped below threshold) → green commit.**

Concretely, at **every** commit:
- **TDD.** Write the discrimination test first; confirm it goes RED against the unpatched code (the red→green log is the anti-vacuity evidence); then apply the fix and confirm GREEN.
- **Green at each step.** `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, and `mix test --exclude eval --seed 0` (plus the relevant `--include eval` tests) all clean before "done."
- **Incremental fail-closed.** A signal flips from fail-OPEN (laundered to passing) to fail-CLOSED (abstain/park on missing) **only in the same slice that lands its real producer**, AND only after the known-good reference (`samples/beads_insight`, `samples/gx`, and where relevant `samples/tasks_service`) still auto-accepts. We never park the reference. If a flip would park the reference, that is a producer/corpus bug to fix — **never** lower the threshold to rescue it.
- **Anti-vacuity contract.** Every discrimination test proves BOTH directions: a BROKEN signal → abstain/reject (asserting the *exact* expected finding category/rule_key), AND a GOOD signal → accept. A test that only asserts the green direction, or only `refute gate.passed?`, is explicitly disallowed.
- **Do not commit or push unless Robert asks.** When he does, branch first if on `main`; commit message trailer ends:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## 3. The convergent finding — WHY M4 exists

All 8 designers, reading the real tree independently, converged on the same diagnosis: **the gate is a green rubber stamp.** It is fully wired (the plumbing runs end-to-end) but the signals it scores are fabricated or absent, so it cannot distinguish a good run from a bad one.

The load-bearing facts, with file:line citations every sub-stream confirmed:

1. **`lib/conveyor/gate/trust_evidence.ex:47-62` launders every unmeasured signal into its passing token.**
   - `calibration(_status) -> :valid` (`:49`)
   - `baseline(_status) -> :green` (`:52`)
   - `integrity(_verdict) -> "trustworthy"` (`:56` — the catch-all swallows `not_assessed` AND `nil`)
   - `replay(_) -> :none` (`:59`)
   - `corpus(_) -> nil` (`:62`)
   So a run with **no measured signals at all** assembles as fully-good evidence.

2. **A clean-everything reference scores 0.925 and always auto-accepts.** `TrustScore` (`trust_score.ex:58-65`) weights integrity 0.30 / calibration 0.20 / baseline 0.20 / replay 0.15 / corpus 0.15; threshold `auto_accept: 0.9` (`:65`). Corpus `nil → 0.5` (`:132`). So the laundered reference scores `0.30 + 0.20 + 0.20 + 0.15 + 0.15·0.5 = 0.925 ≥ 0.9` → `:auto_accept` (verified by arithmetic). **Abstain can never fire** on a real run because the hard gate `trustworthy?/1` (`:105-110`) sees only laundered-good tokens.

3. **The producers are stubs or missing.**
   - `BaselineHealth` is doubly vacuous: the station (`stations/baseline_health.ex:15`) calls `run!()` with no `runner:` (default runner `exit_code: 0` → always pass), AND `baseline_suites/1` filters for `:baseline_regression` suites that **no production code creates** → `Enum.all?([], …) == true` → `:passed`.
   - `AcceptanceCalibration` **fabricates**: the station (`stations/acceptance_calibration.ex:15`) calls `run!(blob_root:)` with no runner (default `exit_code: 1`) → the false-branch emits `status: :valid` + `expected_failures` **without running anything** — manufacturing exactly the `(valid AND expected_failures != [])` the gate guard wants.
   - `replay_divergence` and `corpus_pass_rate`: `trust_evidence.ex:30-31` reads them from slice output, but **no `lib` code writes either** — `serial_driver.ex:147` hardcodes the report-level `replay_fidelity.status = "matched"`.
   - IntegritySentinel: only 2 of 10 probes (`source_mutation`, `hermeticity`) ever receive an observation; `verify.ex:10` admits only those two.

4. **The hermetic backend is never used on the live path.** `RunSpecAssembler.augment_station_plan/6` (`run_spec_assembler.ex:125-130`) builds the verify-station input with no `backend`/`docker_image`/`network` keys → the live gate is always `:local` → hermeticity is omitted → `not_assessed` → laundered to `"trustworthy"`. (`first_light_production_loop_test.exs:84-87` asserts the live loop emits `integrity_verdict == "not_assessed"`.)

5. **Only 4 of 14 gate stages are live.** `serial_driver.ex:31-36` runs `[ContractLock, DiffScope, SecretSafety, TestExecution]`. The other 10 stages exist but are dormant; the `:policy_blocked` and critical stop-the-line Finalizer branches (`finalizer.ex:181-197`) are dead for everything except a secret. Three divergent hardcoded stage lists (SerialDriver, MidflightCheck, AttemptLoop) drift independently.

6. **The MutantGauntlet only discriminates the behavioral subset.** `mutant_gauntlet.ex:29` runs `[TestExecution]` only; the 5 static-stage mutants are recorded by id into `deferred_static_stage` and never actually run through their stages. And `RunGateCanary` *looks* like it does static discrimination but its `patch_set` carries no `changed_files`, so every static stage sees an empty list and passes — a looks-wired-but-vacuous harness.

7. **Two data-integrity bugs sit under the substrate M4 is meant to make trustworthy.** `BackEdge.create_edge!` (`back_edge.ex:69`) hashes `edge_sha256` over a map including the per-finalization nonce `gate_result_id` (`:44`), so every re-finalization mints a duplicate provenance edge (dr1m.1.2). The artifact-projection migration (`20260620110000`) creates unique indexes with no dedupe step and an unsafe `down` (dr1m.8) — latent until a populated, non-Sandbox DB exists.

**The thesis tie-in (HUMAN.md north star):** Conveyor's bet is that it sits on the field's hardest unsolved problem — trustworthy autonomous verification when no human is watching — with the machinery already built and **dormant**. M4 is the activation: it does not build a new verifier; it makes the existing one stop lying. Until M4, every "green" the factory produces is unverified.

---

## 4. Ratified decisions (Robert, this session — verbatim, binding)

The plan MUST honor these exactly:

**Decision 1 — SCOPE = MAXIMAL.** Cover the full M4 — real trust producers + real abstain + hermetic gate + MutantGauntlet static-stage extension, PLUS wire ALL 14 gate stages live with the `policy_blocked` / critical-stop Finalizer branches reachable, PLUS the data-integrity fixes (dr1m.1.2, dr1m.8).

**Decision 2 — POSTURE = INCREMENTAL FAIL-CLOSED.** Today unmeasured/unassessable trust signals fail OPEN (`trust_evidence.ex` launders them to the passing token). M4 flips them fail-closed, but INCREMENTALLY: flip each signal to fail-closed ONLY once its real producer exists AND the known-good reference (`samples/beads_insight` + `samples/gx`) still auto-accepts. Re-tune weights/threshold against that reference at each step. Stay green at EVERY commit. Keep a principled taxonomy: *"genuinely not assessable on this backend"* → `not_assessed`/NON-blocking (e.g. hermeticity when docker absent), distinct from *"should be measured but the producer is missing"* → fail-closed/abstain. The slice shape is: wire one real producer → flip that signal fail-closed → discrimination test (broken signal → park, good signal → accept) → re-tune → green commit.

**Decision 3 — HERMETIC BACKEND = `docker --network=none` ONLY** (already implemented in `ToolchainRunner` with an honest 6-control hermeticity observation). NOT `unshare -n` (Linux-only, unimplemented, dropped). Build a docker-availability check that ABSTAINS (`not_assessed` → park) rather than false-passing when docker is absent. Use the `ToolchainRunner` lighter docker path, NOT the hardened `DockerRunner` lifecycle (that is a separate, larger concern).

**Decision 4 — PRODUCER-LESS STAGES.** Build REAL REQUIRED producers for `provenance_attestation` (from existing patch/artifact digests) and `canary_freshness` (emit a health record from the MutantGauntlet/gate-canary work). Wire `reviewer_aggregation` ADVISORY (non-blocking); flag a real reviewer producer as a Track-B/fleet or AI-reviewer follow-on — independent human reviews do not fit a solo width-1 autonomous loop.

**Decision 5 — EXIT/VALIDATION.** HARD blocking exit = zero false-pass on the FULL canary corpus (behavioral + static) in CI via `mix conveyor.eval.scorecard --gate` + every discrimination test green + abstain proven to fire ($0, deterministic). THEN a bounded live-Codex pass (a few runs on beads/gx) to MEASURE first-pass-gate-success / dispute-rate / parked-rate (reported, NOT a hard gate — live Codex is stochastic; the ROADMAP warns against coupling a milestone exit to agent reliability). PLUS the cheap external-buggy-commit catch-rate falsifier probe (the activated gate must catch real planted defects) — only meaningful AFTER activation.

**Secondary decisions (Claude, overridable by Robert):**
- `replay_divergence` = a REAL per-slice recorded-vs-replayed digest producer (high-leverage; it is a hard auto-accept gate; closes dr1m.1.4).
- `corpus_pass_rate` = from cassette-corpus fidelity initially; flag a Genome historical-rate as a later upgrade.

---

## 5. Glossary

Numbered and defined so a zero-context agent can follow every section.

- **TrustScore** (`lib/conveyor/gate/trust_score.ex`) — the weighted scorer over five evidence signals. Weights: integrity 0.30 / calibration 0.20 / baseline 0.20 / replay 0.15 / corpus 0.15 (sum 1.0). Threshold `auto_accept: 0.9`. Produces a `band` (`:auto_accept` | `:abstain`) and a numeric `score`. Auto-accept requires BOTH the hard gate `trustworthy?/1` (every non-corpus signal unambiguously good) AND `score >= 0.9`.
- **TrustEvidence** (`lib/conveyor/gate/trust_evidence.ex`) — assembles the `TrustScore.evidence()` map from a slice's raw `output` map via `from_run_output/1`. **This is where the laundering lives** (it defaults absent signals to their passing token). M4 makes it stop laundering.
- **`trustworthy?/1`** (`trust_score.ex:105-110`) — the HARD auto-accept gate: requires `integrity_verdict == "trustworthy"` AND `calibration == :valid` AND `baseline == :green` AND `replay == :none`. `corpus_pass_rate` is deliberately excluded (so cold-start never blocks). Any signal failing its clause forces `:abstain` regardless of score.
- **abstain / auto_accept band** — `:auto_accept` = the gate auto-merges (passed + trustworthy + score ≥ threshold). `:abstain` = the gate "parks" the slice for a human (passed gate, but a trust signal is missing/bad). The Finalizer maps `:abstain` → `RunAttempt.outcome = :abstained` + `Slice.state = :parked`, mints no provenance/trust-bundle.
- **The not_assessed / fail-closed taxonomy** (Section 6) — the four states a trust signal can be in. The keystone distinction: **`not_assessed`/NON-blocking** ("genuinely not assessable on this backend", a positive recorded N/A declaration) vs. **fail-closed/abstain** ("should be measured but the producer is missing/empty"). A signal absent for the latter reason routes to its *abstaining* token, never its passing token.
- **The 14 gate stages** (`droid-wiki/systems/gate.md:76-118` numbering): (1) workspace_integrity, (2) diff_scope, (3) observed_risk, (4) policy_compliance, (5) secret_safety, (6) build_install, (7) test_execution, (8) acceptance_mapping, (9) contract_lock, (10) code_quality_delta, (11) run_check, (12) provenance_attestation, (13) reviewer_aggregation, (14) canary_freshness. Live today: 2, 5, 7, 9. M4-exit: **9 required-live** (1, 2, 3, 4, 5, 7, 8, 9, 11) + **5 advisory** (6 build_install, 10 code_quality_delta, 13 reviewer_aggregation, AND 12 provenance_attestation + 14 canary_freshness which are advisory-with-gated-required-flip per Open Decision 16 — real producers built + proven, blocking flip deferred to early M5).
- **IntegritySentinel 10 probes** (`lib/conveyor/verification/integrity_sentinel.ex`) — the anti-vacuity oracle folding 10 probe observations into a verdict (`trustworthy | suspect | not_assessed | untrustworthy`): `base_calibration`, `repeatability`, `hidden_dependency`, `mount_boundary`, `mapping`, `required_artifacts`, `falsifier_survival`, `falsifier_preservation`, `source_mutation`, `hermeticity`. Only `source_mutation` + `hermeticity` are wired today.
- **MutantGauntlet** (`lib/conveyor/eval/mutant_gauntlet.ex`) — the CI honesty harness: applies known-defect mutant patches to a sample and asserts the gate catches each (`false_pass_rate`, blocking, target 0). Today behavioral-only; M4 extends it to the 5 static-stage mutants.
- **Hermeticity / the 6 controls** (`toolchain_runner.ex:241-250` `hermeticity_observation/1`) — the docker-only honest observation over `network / clock / rng / ordering / locale / shared_state` (atoms `:blocked/:controlled/:seeded/:stable/:pinned/:isolated`). Attached only under `:docker`; omitted under `:local` (→ `not_assessed`).
- **Discrimination test** — a test proving the gate **discriminates**: a BROKEN signal → abstain/reject (asserting the exact finding category), AND a GOOD signal → accept. The anti-vacuity contract; a one-directional test is disallowed.
- **The known-good reference (beads / gx)** — `samples/beads_insight` (7 slices, `reference_full.patch` + per-slice patches), `samples/gx` (7 per-slice reference patches, **no `reference_full.patch`**, no `mutants.json`), and `samples/tasks_service` (the gauntlet's primary, `mutants.json` known_good). These greenfield references MUST auto-accept at every M4 commit — the `loop_integrity` invariant.

---

## 6. Design spine — the not_assessed / fail-closed taxonomy

This is the **single load-bearing principle** every sub-stream reuses. It is owned by sub-stream A (which writes the contract into `from_run_output`) and consumed by B, C, D, E. It is pulled up here, in front, because mis-classifying a signal is the most likely way to either (a) park the reference (fail-closed where you should be non-blocking) or (b) re-launder a vacuity (non-blocking where you should be fail-closed).

**The four states a trust signal can be in:**

| State | Meaning | `from_run_output` emits | TrustScore component | `trustworthy?` gate | Blocks auto-accept? |
|---|---|---|---|---|---|
| **measured-good** | producer ran, signal positive | the GOOD token (`:valid` / `:green` / `:none` / `"trustworthy"` / float ≥ band) | 1.0 (or the float) | passes its clause | **No** |
| **measured-bad** | producer ran, signal negative | the BAD token (`:invalid` / `:red` / `:diverged` / `"suspect"`/`"untrustworthy"`) | 0.0 (or 0.5 for `suspect`) | **fails** its clause | **Yes → abstain** |
| **not-assessable-on-backend** | signal genuinely cannot be measured here (e.g. hermeticity, no docker; replay, no recorded baseline) — NON-blocking by design | `:not_assessed` / `:unknown` / `nil` (the dedicated middle token) | 0.5 | **NOT in `trustworthy?`** for these specific non-blocking signals (owner keeps it out) | **No** (lowers score) |
| **should-be-measured-but-missing** | the producer SHOULD have run and didn't, or ran and returned nothing — the fail-closed case | the BAD/abstaining token (NOT the passing one, NOT laundered) | 0.0–0.5 driving abstain | **fails** `trustworthy?` | **Yes → abstain** |

> **How row-3 is ACTUALLY realized (read WITH the table — the row is a simplification, and reading it literally is a known trap):** the literal "`0.5` / NOT in `trustworthy?` / non-blocking" mechanism is realized by exactly ONE signal — **corpus** (scorer-level `corpus_score(nil) = 0.5`, genuinely excluded from `trustworthy?`). It does NOT describe the other "not-assessable" cases: (a) **hermeticity** under `:local` is handled by *removing* the probe from the backend-dependent `required_probes` set (C1), so the IntegritySentinel verdict resolves to `"trustworthy"` (=**1.0**, NOT 0.5) and integrity stays a HARD `trustworthy?` requirement — there is no integrity sub-component to set to 0.5; (b) for an **always-assessable** signal (calibration / baseline / replay), a `:unknown`/`:not_assessed` token *FAILS* `trustworthy?` (fail-closed → abstain) — it is NOT the non-blocking 0.5 the row implies. So row-3's "non-blocking 0.5" applies ONLY to a signal the owning sub-stream has EXPLICITLY excluded from `trustworthy?` because it is genuinely backend-N/A — **never** to a missing always-assessable signal, and **do not** try to give integrity a 0.5 non-blocking contribution (A1 forbids it; traps 12/13 warn against it). The per-signal map below is authoritative; this row is the intuition.

**The single rule that distinguishes the bottom two rows (the whole keystone):**

> A signal is **not-assessable** only when the producer *declares* it cannot run on this backend (a positive, recorded "N/A on this backend" observation). A signal is **fail-closed/missing** when the producer was *expected* to run and the output key is simply absent or empty. `from_run_output` must never default an **expected** signal to its passing token. The default for an expected-but-absent signal is the **abstaining** token; the `not_assessed` token is reserved for an *explicit* backend-N/A declaration.

**Why `not_assessed` is non-blocking but `missing` is blocking, given `trustworthy?` hard-requires the good token:** the resolution is per-signal placement:
- **Always-assessable signals** (calibration, baseline, integrity-source-mutation, replay-per-slice, provenance head-tree/manifest): there is no not-assessable row — absence is always `missing` → fail-closed, and `trustworthy?` keeps hard-requiring the good token.
- **Genuinely-backend-N/A signals** (hermeticity under `:local`, replay with no recorded baseline yet, corpus on cold start): the **owning sub-stream excludes them from `trustworthy?`** when not-assessable (exactly as `corpus_pass_rate` already is), so they contribute 0.5 to the score but do not hard-block — and the owner proves the reference still auto-accepts on the backend where the signal is N/A. (A owns the *contract*; **D** owns hermeticity's/integrity's placement and the integrity-clause un-laundering flip, B owns replay/corpus's, E owns provenance container-material's.)

> **CANONICAL OWNERSHIP OF THE INTEGRITY UN-LAUNDERING FLIP (state once; referenced everywhere — every contradicting line in this doc is corrected to match this):** `TrustEvidence.integrity/1` is un-laundered by **D4 ONLY**, co-shipped in ONE atomic commit with **C1** (the first clean integrity-probe admission) — this is the **`{D4 + C1}` atomic commit at M4.8**. **D3** (the docker producer) is a PREREQUISITE landed *earlier* in **M4.7**; it is **NOT** part of the atomic commit (M4.7 lands D1/D2/D3 while integrity is still laundered, keeping the reference at 0.925; the atomic M4.8 commit is `{D4 + C1}` only). Sub-stream **A (A1)** un-launders ONLY **calibration + baseline** and **LEAVES integrity laundered to `"trustworthy"`** until D4. Sub-stream **B** un-launders/owns ONLY **replay + corpus**, never integrity. There is no "B flips integrity", no "C flips integrity", and no "A1 flips integrity" anywhere in M4 — if you read such a clause, it is stale and superseded by this statement.

**Per-signal classification at M4 exit (the map every sub-stream agrees on):**

| Signal | Owner | Always-assessable? | Absent → |
|---|---|---|---|
| calibration | A | Yes | fail-closed (`:not_assessed` token, fails `trustworthy?`) |
| baseline | A | Yes (a slice with zero baseline suites → `:unknown` → fail-closed *park*) | fail-closed |
| integrity: source_mutation | C | Yes (backend-agnostic) | fail-closed |
| integrity: mount_boundary (`:local` honest def = locked-path writes) | C | Yes (locked-path def) | fail-closed |
| integrity: hermeticity | D | **No** — docker-only | `not_assessed`/non-blocking under `:local`; **fail-closed when docker required but absent**. (D4 owns the integrity-clause un-laundering flip; co-ships with D3+C1.) |
| replay_divergence (first run = `:none` by construction) | B | Yes per-slice; unfingerprintable → `:unknown`/fail-closed | `nil` (no producer) → non-blocking staged default; unrecognized → fail-closed |
| corpus_pass_rate | B | **No** — BOOST-only, excluded from `trustworthy?`; significance floor (`< 5` cassettes → `nil`) | non-blocking |
| provenance container-image material | E | **No** under `:local` | `not_assessed` under `:local`; required under `:docker` |

---

## 7. MASTER SEQUENCING — the execution spine

This is THE order. It interleaves the 8 sub-streams' ~50 slices into green-committable sub-milestones (M4.1 … M4.13) that respect the `depends_on` graph. The governing principle: **foundations first (the taxonomy + the re-calibration harness + the discrimination harness), then producers that depend on them, then stage-wiring, then MutantGauntlet validation, then the hermetic gate, then the data-integrity ride-along, then exit/validation last.**

**The dependency graph (condensed):**
- A (trust-core) depends on nothing → it is the keystone (taxonomy, non-laundering, re-tune protocol, discrimination harness). **Everything imports A1/A6/A7.**
- B (replay/corpus) depends only on A's re-calibration ledger; self-contained otherwise.
- C (integrity probes) has a **HARD** dependency on **D4** (the integrity un-laundering flip — owned by D, NOT A): the un-laundering must land before/with C's first probe admission, or every C discrimination test is vacuous. **C1 and D4 co-ship atomically** (see the re-cut master sequence). Soft on E (workspace-integrity / acceptance-mapping data).
- D (hermetic gate) depends on A (taxonomy coordination on the OTHER `trust_evidence.ex` clauses — calibration/baseline/replay/corpus) and B (replay-digest ordering); **D owns the integrity-clause un-laundering flip (D4), co-shipped with D3 + C1**.
- E (all 14 stages) depends on F (canary producer composition + the full-corpus gate) and on D (real abstain — keep the reference auto-accepting). It is the largest sub-stream.
- F (mutant gauntlet) depends on E (live gate stages) — and E depends on F's canary producer; they are **co-developed** around the shared `MutantContext`/`Pipeline` seam. In practice E0 (the Pipeline) + F1 (the MutantContext) land first, then E's stage-wiring and F's stage-discrimination interleave.
- G (data integrity) depends on nothing — a non-blocking ride-along appendix; lands last-but-one.
- H (exit/validation) depends on **all of A–G** — it is the acceptance harness; lands last.

> **Note on cross-stream `depends_on` aliases:** designers used slightly different names for the same streams (A appears as `A-trust-producers` / `A-recalibration` / `A-trust-taxonomy`; B as `B-replay-corpus` / `B-replay-divergence` / `B-abstain-end-to-end` / `D-replay-corpus`; C as `C-integrity-probes` / `C-hermetic-gate`; D as `D-hermetic-gate` / `D-hidden-dependency-hermeticity` / `D-real-trust-abstain`; E as `E-gate-stages` / `E-live-gate` / `E-all-14-stages`; F as `F-mutant-gauntlet`). The canonical mapping is A=trust-core, B=replay-corpus, C=integrity-probes, D=hermetic-gate, E=all-14-stages, F=mutant-gauntlet, G=data-integrity, H=exit-validation. The sequencing below uses the canonical letters.

### The ordered sub-milestones

Each sub-milestone is a green-committable cluster. "Touches re-tune?" flags whether a TrustScore weight/threshold change is in play (the answer is almost always *no* — see Section 9).

---

**M4.1 — Foundations: taxonomy, non-laundering, re-tune protocol, discrimination harness (A1, A7, A6).**
- **Slices:** A1 (fail-closed taxonomy + non-laundering `from_run_output/1`), A7 (the `Conveyor.Test.TrustDiscrimination` harness), A6 (the re-tune protocol + `reference_auto_accept_test.exs` anchor).
- **Dependency rationale:** these are the keystone artifacts every other sub-stream imports (`assemble/1`, `assert_discriminates`/`band_of_output`, the re-tune anchor table). They must merge first. A1 flips **calibration + baseline** non-laundering immediately (A owns those producers in A2/A4); **integrity** non-laundering is owned by **D4** and flipped in the atomic M4.8 {D4 + C1} commit (NOT by A1, NOT by B), so A1 KEEPS integrity laundering to `"trustworthy"` until M4.8 — honoring incremental fail-closed (and per the F13 honesty flag, the reference's integrity is fabricated, not earned, until M4.8).
- **Green criterion:** `trust_evidence_test.exs` + `trust_score_test.exs` rewritten (the two "unmeasured → non-blocking" tests that *encoded the leak* are deleted/inverted); `reference_auto_accept_test.exs` green at score 0.925; full `mix test --exclude eval --seed 0` green.
- **br closed:** advances dr1m.1.3 (not yet fully closed).
- **Touches re-tune?** No (weights/threshold unchanged; A1 changes evidence assembly only).

**M4.2 — Real baseline producer + flip (A2, A3).**
- **Slices:** A2 (real `BaselineHealth` runner + materialize `:baseline_regression` suites for ALL THREE sample corpora in the same PR), A3 (flip baseline fail-closed + verify reference + end-to-end finalizer test).
- **Dependency rationale:** depends on A1 (non-laundering) + the A6 protocol. A2 must land the suites for all three corpora so A3's flip never parks the reference (a slice with zero baseline suites → `:unknown` → abstain *park*; the reference must have suites).
- **Green criterion:** baseline discrimination tests green (red baseline → abstain; no suite → abstain; green → accept); reference scores 0.925 → auto-accept; `scorecard --gate` exit 0.
- **br closed:** dr1m.1.3 (baseline half).
- **Touches re-tune?** No (reference stays 0.925).

**M4.3 — Real calibration producer + flip + empty-suite hard-fail (A4, A5, A7d).**
- **Slices:** A4 (real `AcceptanceCalibration` runner over the *base* checkout — kills the fabrication), A5 (flip calibration fail-closed + verify + finalizer test), A7d (dr1m.7 empty-acceptance-suite hard-fail at THREE layers: eval `ToolchainRunner.suite/3`, production `VerificationRerunner`, gate `test_execution`).
- **Dependency rationale:** A4/A5 depend on A1. A7d is defense-in-depth and reveals that production uses `VerificationRerunner` (the third layer the seed facts did not name). A4 is the single most dangerous stub (it fabricates `:valid`). **PRE-FLIP GATE (mandatory): A4 is its own green commit that runs the real `AcceptanceCalibration` runner over the BASE checkout for all three corpora and RECORDS/prints the per-corpus base-red verdict WITHOUT yet failing closed. A5 (the flip) proceeds ONLY if all three corpora are genuinely red-on-base.** If any corpus is NOT red-on-base, that is a real defect in the reference's locked tests (they don't assert the new behavior) — the fix is to **repair the reference's acceptance tests** (make them genuinely fail on base), NOT to re-tune, NOT to skip the flip, NOT to revert to fabrication. This is the "stop and fix the corpus" fork; A5 does not land until A4's recorded verdict is all-red-on-base.
- **Green criterion:** A4 records all-three-corpora base-red verdict (the pre-flip gate); calibration discrimination tests green; empty-acceptance-suite tests green at all three layers; reference calibrates to `:valid` on all three corpora; `scorecard --gate` exit 0 with `false_pass_rate == 0`.
- **br closed:** dr1m.1.3 (fully — calibration + baseline now real + fail-closed); dr1m.7.
- **Touches re-tune?** No.

**M4.4 — Real replay + corpus producers (B1, B2, B3, B4).**
- **Slices:** B1 (real per-slice `replay_divergence` producer + `BaselineStore` + the fail-closed flip + the `EventNormalizer` extraction), B2 (`corpus_pass_rate` from cassette fidelity, BOOST-only, with the significance floor `< 5 → nil`), B3 (replace the report-level `replay_fidelity.status = "matched"` hardcode with a computed value), B4 (Genome historical-rate upgrade flag — tracking only, no code).
- **Dependency rationale:** depends on A's re-calibration ledger (folds B's stated numbers in). Self-contained otherwise; can run in parallel with M4.2/M4.3 after M4.1. Land B before C/D so the replay/corpus signals are real when the integrity work re-tunes.
- **Green criterion:** `slice_divergence_test.exs` (incl. the mutated-baseline → `:diverged` falsifier) green; the `m1_codex` tampered-third-run end-to-end park-on-divergence green; the 4 cross-run determinism tests UNCHANGED-green (normalizer extraction is byte-identical); corpus significance-floor tests green; reference auto-accepts at every corpus size.
- **br closed:** dr1m.1.4 (both the gate half via B1 and the report-field half via B3).
- **Touches re-tune?** No (weights/threshold unchanged; fail-closed achieved by taxonomy + significance floor, not re-tuning).

**M4.5 — Pipeline unification + verdict column (E0, F1).**
- **Slices:** E0 (the `Conveyor.Gate.Pipeline` single-source 14-stage table with per-stage `required?`; unify SerialDriver + MidflightCheck + AttemptLoop; add the `GateResult.verdict` column + migration; all 10 dormant stages ship at `required?: false`, behaviorally == today's 4-live), F1 (the DB-free `Conveyor.Eval.MutantContext` assembler skeleton + `changed_files` derivation).
- **Dependency rationale:** E0 and F1 are the shared seams the rest of E and F build on. They are pure plumbing (E0 stays byte-equivalent to today; F1 is a no-behavior-change refactor). They must precede every stage-wiring slice.
- **Green criterion:** `pipeline_test.exs` green (single source; midflight allowlist intact; behaviorally == legacy 4-live); `verdict` written by the Finalizer; `mutant_context_test.exs` green (changed_files parsed from patch headers); existing serial_driver/midflight/attempt_loop/finalizer tests unchanged-green.
- **br closed:** none yet (enabling).
- **Touches re-tune?** No.

**M4.6 — Static-stage wiring + MutantGauntlet static discrimination (E1–E5 ⨉ F2–F4, interleaved; F5 CUT).**
- **Slices:** the cheap, deterministic required stages, each flipped `false → true` in `Pipeline.@full` in the same commit as its producer + symmetric GOOD/BROKEN discrimination test, with F running the matching mutant through it:
  - E1 workspace_integrity (head_tree_sha256 producer) ‖ —
  - E2 acceptance_mapping (surface acceptance_criteria) ‖ —
  - E3 run_check (artifact_contents + manifest producer) ‖ F4 (`tool_output_injection_ignored`, `repo_prompt_injection_ignored` rerouted)
  - E4 observed_risk (committed default ReviewPolicy per sample) ‖ —
  - E5 policy_compliance (tool_invocations producer; makes `:policy_blocked` reachable) ‖ F2 (`forbidden_policy_edit` + plan.yml glob fix)
  - F3 (`ContractLock` synthetic bundle ‖ `test_weakened_or_deleted`); **F5 is CUT — `code_quality_delta` stays advisory (no fixture-oracle hard catch); `new_codescent_high_risk` marked advisory (Open Decision 17)**
- **Dependency rationale:** E1–E5 are independent of each other after E0 and parallel-safe; each makes one stage required. F2–F4 wire the *4 hard-catch* static stages into the gauntlet's `@stages` and prove the matching mutant is caught for the *right reason* (`caught_by_expected?`). The two streams share the `MutantContext` context-key contract (F is DB-free synthetic; E is DB-backed real — same keys, different producers). **C cannot start its first probe admission until D4 lands (the atomic M4.8) — not yet reached here.**
- **Green criterion:** each stage's GOOD half (real reference → passes, gate accepts, no false-park) AND BROKEN half (real mutant → fails with the EXACT `expected_catch.category`, gate fails) green; the canary corpus catches each enabled non-advisory static mutant live; reference auto-accepts through the growing required set; `scorecard --gate` green.
- **br closed:** dr1m.E1, dr1m.E4, dr1m.E5, dr1m.E8 (acceptance_mapping), dr1m.E11 (run_check); F's br-m4-mg-002..005 (br-m4-mg-006/007 RETIRED — F5 cut).
- **Touches re-tune?** No (wiring stages affects `passed?` upstream of trust, never the trust band).

**M4.7 — Hermetic-gate foundation, still-laundered (C0 + D1, D2, D3).**
- **Slices:** C0 (harden `source_mutation` discrimination end-to-end through the trust gate — needs NO un-laundering; it asserts the already-live probe, safe alone), D1 (harden `docker_available?/0` to probe the daemon, timeout-wrapped, `:persistent_term`-cached), D2 (docker-absent ABSTAIN fallback via `Conveyor.Gate.HermeticBackend`), D3 (thread `backend=docker` into `RunSpecAssembler`, gated `hermetic_gate` opt, default false in tests / true at the conductor).
- **Dependency rationale:** these all stay green **while integrity is still laundered to `"trustworthy"`** — D3 alone leaves `:local` runs auto-accepting (the integrity catch-all still launders `not_assessed → "trustworthy"`), so the reference's score is unchanged at 0.925 at every commit here. C0 hardens the one already-live integrity probe and needs no un-laundering. **D4 is deliberately NOT in this sub-milestone** — it co-ships atomically with C1 in M4.8 (see below). This is the buildable order: lay the docker producer + abstain fallback first, then flip un-laundering and admit the first real probe together.
- **Green criterion:** C0 discrimination (mutated source → abstain; clean → accept) green; D1 daemon-probe tests green; D2 `HermeticBackend.decide` tests green (docker-absent → `{:unavailable, _}`, NOT `{:local,_}`); D3 assembler tests green (hermetic_gate off → unchanged; on+docker → backend=docker; on+absent → abstain key). The reference still auto-accepts at score **0.925** at every commit (integrity still laundered).
- **br closed:** C-integrity.0; advances 8hx7 (moot under docker via D3).
- **Touches re-tune?** No (integrity still laundered; reference unmoved at 0.925).

**M4.8 — ATOMIC un-laundering co-ship: {D4 + C1} (the single most load-bearing commit-chain in M4).**
- **Slices (ONE atomic commit-pair, in this order within the same green chain):** **D4** (flip `TrustEvidence.integrity/1` fail-closed — stop laundering `not_assessed`/`nil` to `"trustworthy"`) **AND** **C1** (admit `mount_boundary` with a clean producer + make `required_probes(backend)` backend-dependent so hermeticity is only required under `:docker` + update `first_light_production_loop_test.exs:87` `not_assessed → trustworthy`). These TWO land together so the reference never commits the parked state.
- **Dependency rationale (the interlock, stated mechanically):** D4 alone un-launders `not_assessed`, dropping the reference's integrity component 1.0 → 0.5 → score **0.775 < 0.9 → PARK** (forbidden). C1 alone is vacuous while D4 has not landed (a broken integrity signal still scores 1.0, so "broken → park" cannot be proven). Co-shipped: D4 un-launders AND C1's clean `mount_boundary` + `source_mutation` (on `:local`, backend-dependent `required_probes` drops hermeticity) yield a genuine `trustworthy` (1.0) → reference returns to **0.925**. The reference goes **0.925 (laundered) → [transient, uncommitted] → 0.925 (genuine trustworthy)** — it **never commits 0.775**. The backend-dependent `required_probes(backend)` change is mandatory in C1 — without it the `:local` reference can never reach `trustworthy` (hermeticity unobserved on `:local` pins the verdict to `not_assessed` forever) and every admission is vacuous.
- **Green criterion:** the 3 vacuity-encoding tests inverted in the SAME commit (`integrity_evidence_test.exs:12-17`, `trust_evidence_test.exs:45-47`, `:50-59`); `reference_auto_accept_test.exs` stays green at **0.925 → 0.925, never 0.775** across the pair; docker-hermetic reference → `trustworthy` → auto-accept; `:local`/non-hermetic/docker-absent → `not_assessed` → abstain → park; C1 `mount_boundary` discrimination green (locked-path write → abstain; clean → accept); `sentinel_evasion_rate == 0`.
- **PRECONDITION GUARD for C1 (mechanical, in the C1 test):** before admitting any probe, assert `band_of_output(%{}) == :abstain` (integrity already un-laundered by D4). If it is still `:auto_accept`, D4 has not landed in this commit — **STOP** (the admission would be vacuous).
- **br closed:** 8hx7 (the integrity/hermeticity half of dr1m.1 / dr1m.1.3); C-integrity.1.
- **Touches re-tune?** **No** — the docker-hermetic / `:local`-clean reference reaches a genuine `trustworthy` (1.0) and stays at 0.925; weights/threshold UNCHANGED (the producers supply the asserted verdict; D4 needs no re-tune because C1's clean probe lands in the same commit).

**M4.8b — Rest of the integrity probes + rest of the hermetic gate (C2, C3, C4 ‖ D5, D6, D7).**
- **Slices:** C2 (`mapping` producer from contract acceptance criteria), C3 (`required_artifacts` scoped to verify-stage artifacts), C4 (`falsifier_preservation` + `falsifier_survival` from the Test Architect report); D5 (fix br 8hx7 venv provenance), D6 (LIVE-path discrimination test through the real assembler/stations), D7 (CI decision + `hermetic_false_pass_rate` scorecard metric + docker-enabled CI job). Then **C5** (consolidated re-tune + full-corpus zero-false-pass proof + planted-defect catch-rate).
- **Dependency rationale:** each C2–C4 admission defensively re-verifies the reference stays at 0.925 (integrity is now genuinely un-laundered, so each is non-vacuous). D5–D7 finish the hermetic gate (venv provenance, live-path proof, CI enforcement). C5 is the capstone re-tune (expected no-op) and the full-corpus / external-falsifier proof. D depends on B (replay-digest ordering preserved by construction; locked in D6).
- **Green criterion:** each C probe's discrimination test green (broken observation → `untrustworthy` → abstain with the exact `rule_key`; clean reference → `passed`); D6 live-path discrimination green (docker-hermetic → accepted; network-open → abstained+parked; docker-absent → abstained+parked); `hermetic_false_pass_rate == 0` enforced via a REAL docker CI run; the `:eval` reference auto-accept proof green; `sentinel_evasion_rate == 0`, `sentinel_probe_coverage == 1`.
- **br closed:** C-integrity.2 … C-integrity.5; advances dr1m.1 (producer side).
- **Touches re-tune?** Defensive only (C5 verifies the reference stays 0.925; no number change expected).

**M4.9 — Provenance + canary producers (advisory, built + discriminating) + advisory stages (E6, E7, E8).**
- **Slices:** E6 (`provenance_attestation` — build the real `GateProvenanceContext` assembler from existing digests + backend-aware container-material taxonomy; wire ADVISORY with the pre-flip digest audit defined; required-flip gated/deferred), E7 (`canary_freshness` — build `RunGateCanary`/`GateHealth` producer + the `ensure_fresh_canary!` conductor hook + the real `Pipeline.code_sha256/0` freshness key; wire ADVISORY; required-flip gated on the conductor hook + a fresh row, deferred), E8 (`build_install`, `code_quality_delta`, `reviewer_aggregation` ADVISORY with honest `not_assessed` downgrades + flagged Track-B producers).
- **Dependency rationale:** E6/E7 need E0 (the Pipeline). E7's producer + conductor hook are PINNED to E7 (created here, consumed by F later). E8 is the honest advisory line: three stages genuinely lack a width-1 producer. **All of E6/E7/E8 are advisory (`required?: false`) at M4** — E6/E7 build + PROVE-discriminate their real producers (BROKEN-half tests land) but defer the required-flip behind a pre-flip verification (blast-radius brake; Open Decision 16).
- **Green criterion:** provenance discrimination green at the STAGE level (docker requires container-image material; `:local` emits non-blocking `provenance_container_not_assessed`; BROKEN → exact missing-category finding); canary_freshness discrimination green at the STAGE level (stale/false-negative → finding; `gate_code_sha256` invalidation works); advisory stages execute, record findings, never fail the gate; reference auto-accepts (its `passed?` is unaffected by the advisory stages).
- **br closed:** dr1m.E12, dr1m.E14 (advisory; required-flips gated/deferred); dr1m.E6/E10/E13 (advisory partials).
- **Touches re-tune?** No (gate-stage matrix only, not trust weights).

**M4.10 — Reachability + MutantGauntlet collapse + falsifier (E9, F6, F7, F8).**
- **Slices:** E9 (Finalizer-reachability integration tests: protected-policy edit → `:policy_blocked`; false-negative canary → `:rejected` + stop_the_line incident even with canary advisory; reference → `:accepted`), F6 (collapse to ONE full-corpus `false_pass_rate` over the ENABLED non-advisory mutants — count derived from the manifest, 7 today — with `caught_by_expected?`; rewrite `mutant_gauntlet_test.exs`), F7 (abstain proof + external-buggy falsifier fixture + `:local` hermeticity honesty test), F8 (cross-sample decision — tasks_service-only for M4, recommended).
- **Dependency rationale:** E9 depends on E5 (policy_blocked) + E7 (critical/canary). F6 requires the 4 hard-catch static stages live (F2–F4; F5 cut) + the assembler complete. These prove the previously-dead Finalizer branches are reachable end-to-end and the metric is honest.
- **Green criterion:** both dead branches reachable end-to-end; `false_pass_rate == 0.0` over the full ENABLED non-advisory corpus (manifest-derived count, 7 today) with `caught_by_expected?` (a wrong-reason rejection counts as a false PASS, not a catch); the `full_gate_fixture/1` GOOD-half asset mirrors production `default_gate_context/3` field-by-field.
- **br closed:** br-m4-mg-008..011; contributes to dr1m.E5/E14.
- **Touches re-tune?** No.

**M4.11 — Full-pipeline integration + hard exit gate (E10).**
- **Slices:** E10 (full-pipeline integration over BOTH canary corpora; reconcile the 3 manifest-vs-stage drift cases; emit the blocking `gate_corpus_false_pass_rate`; the structural drift guard + the meta-assertion that the static stages actually ran).
- **Dependency rationale:** the capstone of E — composes E1–E9 with F's harness. Requires every required stage live and every `expected_catch` reconciled to a real stage category.
- **Green criterion:** zero false-positive on the known-good, zero false-negative on the mutants, both samples; `gate_corpus_false_pass_rate` blocking at 0; the meta-assertion proves at least one mutant caught by `policy_compliance`, one by `run_check`, one by `test_execution`.
- **br closed:** finalizes dr1m.E1/E3/E4/E5/E8/E11 (required-live); advances E6/E10/E12/E13/E14 (advisory).
- **Touches re-tune?** No.

**M4.12 — Data-integrity ride-along (G1 always; G2 CONDITIONAL).**
- **Slices:** G1 (dedup `CodeProvenanceEdge` on the 10-field logical tuple; drop both nonces from the digest; required `upsert?: true` + `upsert_identity: :unique_edge_sha256`) — **always in M4** (real Genome correctness bug the re-run/replay loop actively triggers, real end-to-end discrimination test). G2 (new forward-only dedup-safe artifact-projection migration + dedup-safe `down` + the populated-data discrimination test) — **CONDITIONAL on Open Decision 13** (is a durable, populated, non-Sandbox DB in scope before M4 ships?). G2's bug is LATENT — it only bites on a populated non-Sandbox DB, and its test exercises a scratch table, not the real migration path.
- **Dependency rationale:** non-blocking appendix; depends on nothing; touches no verdict. G1 lands as a green commit before exit. **G2 ships in M4 ONLY IF a durable DB is in scope (Decision 13); otherwise G2 DEFERS to the milestone that introduces the durable run-history DB, filed as a tracked follow-on** — do not spend an M4 slice on a latent bug with a scratch-table-only test if Sandbox-only CI is the M4 reality (the likely answer). Resolve Decision 13 FIRST.
- **Green criterion:** `back_edge_dedup_test.exs` (re-mint → no duplicate; different patch → distinct edge) green AND proven red against unpatched code first; (if G2 in scope) `artifact_projection_dedupe_test.exs` green + `mix ecto.migrate && rollback && migrate` round-trips on a throwaway DB; `scorecard --gate` verdict counts byte-identical before/after.
- **br closed:** dr1m.1.2 (G1); dr1m.8 (G2, only if shipped in M4; else deferred-with-tracked-follow-on).
- **Touches re-tune?** No.

**M4.13 — Exit & validation (H1–H7).**
- **Slices:** H1 (DONE.md scaffold + cost note), H2 (full-corpus CI-hard zero-false-pass gate across all samples; fix the `@suite` collision), H3 (re-calibration regression guard in the DEFAULT suite), H4 (end-to-end abstain proof from a REAL broken producer signal, asserted from persisted records), H5 (external-buggy-commit falsifier probe — sterile in-repo sample mutants), H6 (bounded-live measurement protocol + `LiveReport` task — reported, never gated), H7 (finalize DONE checklist + activate falsifier CI canary + meta-test).
- **Dependency rationale:** H depends on **all of A–G** being green. It is the acceptance harness and honesty contract — it does not build producers; it proves they are done. Lands last.
- **Green criterion (the HARD M4 exit):** `mix conveyor.eval.scorecard --gate` exit 0 on the full corpus + every A–F discrimination test green + abstain proven to fire ($0, deterministic) + the external-falsifier probe catches every planted defect (zero false-accepts). THEN the bounded live-Codex pass MEASURES first-pass-gate-success / dispute / parked (reported, not gated).
- **br closed:** dr1m.7 (co-verified); opens the `m4.exit` umbrella.
- **Touches re-tune?** No (H3 *guards* re-tune; it does not change numbers).

---

### Sequencing summary (one-line dependency-respecting order)

```
M4.1  A1 → A7 → A6                         (foundations: taxonomy + harness + re-tune protocol)
M4.2  A2 → A3                              (baseline producer + flip)
M4.3  A4 → A5 → A7d                        (calibration producer + flip + dr1m.7)
M4.4  B1 → B2 → B3 → B4                    (replay + corpus producers)        [parallel-safe after M4.1]
M4.5  E0 ‖ F1                              (Pipeline + MutantContext seams)
M4.6  E1..E5 ⨉ F2..F4                      (static stages wired + gauntlet-discriminated; F5 CUT — code_quality_delta advisory)
M4.7  C0 ‖ D1 → D2 → D3                    (hermetic-gate foundation; integrity STILL laundered, reference auto-accepts)
M4.8  {D4 + C1} ATOMIC                      (un-launder integrity + admit mount_boundary in ONE commit; 0.925→0.925, NEVER 0.775)
M4.8b C2 → C3 → C4 ‖ D5 → D6 → D7 → C5    (rest of integrity probes + rest of hermetic gate + consolidated re-tune)
M4.9  E6 → E7 → E8                         (provenance + canary built ADVISORY w/ gated required-flip + advisory stages)
M4.10 E9 ‖ F6 → F7 → F8                    (reachability + metric collapse + falsifier)
M4.11 E10                                  (full-pipeline integration + hard exit gate; owns the multi-sample --gate + @suite fix)
M4.12 G1 [ + G2 IF durable DB in scope ]   (data-integrity ride-along; G2 CONDITIONAL on Open Decision 13)
M4.13 H1 → H2 → H3 → H4 → H5 → H6 → H7     (exit & validation)
```

> **The one cross-stream interlock — RESOLVED by the atomic M4.8 co-ship (read this; the per-slice C/D notes below defer to it):** C1 (first integrity probe admission) and D4 (the integrity-clause un-laundering flip, owned by D) are mutually load-bearing and **MUST land in the SAME commit** (M4.8). The buildable order is: M4.7 lands D1/D2/D3 (docker producer + abstain fallback) **while integrity is still laundered** — the `:local` reference still auto-accepts at 0.925 because the integrity catch-all still maps `not_assessed → "trustworthy"`. Then M4.8 is a single atomic commit that flips D4 (un-launder) AND C1 (admit `mount_boundary` with a clean producer + backend-dependent `required_probes`) together, so the reference goes **0.925 (laundered) → [transient] → 0.925 (genuine trustworthy)** and **never commits the 0.775 parked state**. A whole-C-before-whole-D (or whole-D-before-whole-C) cut is structurally impossible to keep both non-vacuous AND green — that is why D4 and C1 are pulled out of their home sub-streams into one joint sub-milestone. Mechanical guard in C1: assert `band_of_output(%{}) == :abstain` (integrity already un-laundered) before admitting any probe; if still `:auto_accept`, D4 has not landed — STOP.

---

## 8. The 8 full sub-stream sections

The following 8 sections are the **execution body**, stitched in verbatim with their full per-slice detail preserved. Execute them in the order Master Sequencing dictates (A, B, then E0/F1, then the E⨉F interleave, then C, D, the rest of E, F, G, H). Each is under its own level-2 heading.

---


## A — Trust-vacuity core (the keystone)

> **Sub-stream key:** `A-trust-core`
> **One-line mandate:** Stop the trust-evidence layer from laundering unmeasured signals into passing tokens; build the real producers for the two stubbed signals (BaselineHealth, AcceptanceCalibration); close the empty-acceptance-suite false-PASS (dr1m.7) with defense-in-depth; and establish the two cross-cutting protocols every other M4 sub-stream reuses — the **fail-closed taxonomy** and the **weight/threshold re-tuning protocol** against the green reference.
>
> **Posture (non-negotiable):** INCREMENTAL FAIL-CLOSED. Every commit stays green AND the known-good reference (`samples/beads_insight`, `samples/gx`, `samples/tasks_service`) still auto-accepts. A signal flips fail-closed ONLY in the same slice that wires its real producer. We never park the reference.

---

### Verification of seed facts (done before designing — all CONFIRMED)

I read every named module at the named lines. The seed facts are accurate. Key confirmations and three additions the executor must know:

| Seed claim | Status | Evidence |
|---|---|---|
| `trust_evidence.ex:47-62` launders every unmeasured signal to its passing token | **CONFIRMED** | `calibration(_status) -> :valid` (:49); `baseline(_status) -> :green` (:52); `integrity(_verdict) -> "trustworthy"` (:56, catch-all swallows `not_assessed`); `replay(_) -> :none` (:59); `corpus(_) -> nil` (:62). |
| TrustScore: integrity 0.30 / calibration 0.20 / baseline 0.20 / replay 0.15 / corpus 0.15; band `:auto_accept` iff `trustworthy?` AND `score>=0.9`; not_assessed/missing component → 0.5 | **CONFIRMED** | `@default_weights` :58-64; `@default_thresholds %{auto_accept: 0.9}` :65; band :89; `trustworthy?/1` :105-110; component fallbacks :116/:120/:124/:128/:132. |
| A green-everything reference scores ~0.925 → auto_accept | **CONFIRMED + computed exactly** | corpus nil→0.5 ⇒ `0.30+0.20+0.20+0.15+0.15*0.5 = 0.925`; corpus 0.95 ⇒ `0.9925`; corpus 1.0 ⇒ `1.0`. All ≥ 0.9 → auto_accept. (Ran the arithmetic; see Slice A6 anchor table.) |
| Finalizer abstain branch (`passed? AND abstain?`) parks the slice; opt-in via `:trust_evidence`; producers DO supply it (serial_driver:492, attempt_loop:257) | **CONFIRMED** | finalizer.ex cond :28-42; `trust_score/2` :56-61 returns nil when no `:trust_evidence`; serial_driver `trust_evidence/1` :505-508; attempt_loop :266-268. |
| BaselineHealth double-vacuity | **CONFIRMED** | station :15 calls `BaselineHealth.run!()` with NO `runner:` opt → core default runner `exit_code: 0` (:55) → always passed; AND `baseline_suites/1` (:35-39) filters `suite_kind == :baseline_regression` which **no production code creates** → `Enum.all?([], …) == true` → `:passed`. |
| AcceptanceCalibration fabricates | **CONFIRMED — worse than baseline** | station :15 calls `run!(blob_root:)` with NO `runner:` → core default runner `exit_code: 1` (:64) → `all_green? == false` → false-branch (:25-35) emits `status: :valid` + `expected_failures: test_pack.required_test_refs` **without running anything**. This fabricates exactly the `(status==:valid AND expected_failures!=[])` the gate calibration guard requires (`test_execution.ex:157-171`). |
| Assembler asymmetry | **CONFIRMED** | `run_spec_assembler.ex:109-113` injects only `blob_root` to baseline/calibration; `:115-123` implement gets workspace_path+base_commit+blob_root; `:125-130` verify gets workspace_path+plan_path+test_refs. The verify station (`stations/verify.ex`) is the **working model**: it builds a real `ToolchainRunner` runner from `Workspace.venv_opts()` + injected `workspace_path`/`backend`. |
| dr1m.7 empty-suite → false PASS | **CONFIRMED, and the leak is two-layered** | `toolchain_runner.ex` `suite/3` :332-336: `failed? = Enum.any?(tests, …)`; `[]` → `false` → `"passed"`, `exit_code 0`. `verification_result/3` :88-93 builds `acceptance_tests` by `Enum.filter(tests, &(&1.id in acceptance_ids))` with **no non-empty assertion**, then always emits the `acceptance_locked` suite (:93). Gate backstop (`test_execution.ex`): `require_suite` :123-129 is **presence-only**; `failed_suite_findings` :131-144 treats `status "passed"` as fine; `calibration_findings` :146-179 checks calibration, not suite-emptiness. So an acceptance suite with **zero tests** sails through as passed. |

**Three additions the seed facts did not state (the executor MUST internalize these):**

1. **`VerificationRerunner` inherits the SAME empty-suite leak** (`evidence/verification_rerunner.ex:32-37, 212-218`). This is the runner the **production** gate `test_execution` stage uses (`test_execution.ex:48`), distinct from the eval `ToolchainRunner` the gauntlet uses. dr1m.7's defense-in-depth must cover BOTH producers, or the production path stays leaky while the eval path is fixed. **This is a looks-wired-but-vacuous trap: fixing only `ToolchainRunner.suite/3` makes the gauntlet green while production still false-passes.**

2. **The existing `trust_score_test.exs:55-65` "thin/not_assessed abstains" test is VACUOUS in production.** It feeds `TrustScore.evaluate` a hand-built not_assessed map directly — but `trust_evidence.ex` **never emits not_assessed** (it launders to the passing token first). So the test passes while the real `from_run_output → TrustScore` path it is supposed to protect is broken. Our taxonomy slice (A1) closes this by making `from_run_output` actually emit not_assessed for absent signals, and adds a discrimination test through the **full** `from_run_output → evaluate` path.

3. **The known-good corpus is three samples, not two.** `samples/tasks_service` (the gauntlet's primary, `mutants.json` known_good), `samples/beads_insight` (7 slices, `reference_full.patch` + per-slice patches, used by the docker discrimination test), and `samples/gx` (7 per-slice reference patches). All three must keep auto-accepting through every re-tune. The recalibration protocol (A6) anchors on all three.

---

### The fail-closed taxonomy (the core design artifact — every sub-stream depends on this)

This is the keystone. It defines the **four states** a trust signal can be in, what value each maps to in `TrustScore.evidence()`, and whether it blocks. Other sub-streams (B-integrity/hermeticity, C-replay/corpus, D-provenance/canary/reviewer) classify their signals against this table and reuse the discrimination-harness pattern (A7).

| State | Meaning | `from_run_output` emits | TrustScore component | `trustworthy?` gate | Blocks auto-accept? |
|---|---|---|---|---|---|
| **measured-good** | producer ran, signal is positive | the GOOD token (`:valid` / `:green` / `:none` / `"trustworthy"` / float≥band) | 1.0 (or the float) | passes its clause | **No** |
| **measured-bad** | producer ran, signal is negative | the BAD token (`:invalid` / `:red` / `:diverged` / `"suspect"`/`"untrustworthy"`) | 0.0 (or 0.5 for `suspect`) | **fails** its clause | **Yes → abstain** |
| **not-assessable-on-backend** | the signal genuinely cannot be measured on this backend (e.g. hermeticity with no docker; replay with no recorded baseline). NON-blocking by design. | `:not_assessed` / `:unknown` / `nil` (the dedicated middle token) | 0.5 | **NOT in `trustworthy?`** for these specific non-blocking signals (see note) | **No** (but lowers score; see A6 threshold note) |
| **should-be-measured-but-missing** | the producer SHOULD have run on this backend and didn't, OR ran and returned nothing. This is the fail-closed case. | the BAD/abstaining token (NOT the good one, NOT laundered) | 0.0–0.5 driving abstain | **fails** `trustworthy?` | **Yes → abstain** |

**The single rule that distinguishes the bottom two rows** (this is the whole keystone):

> A signal is **not-assessable** only when the producer *declares* it cannot run on this backend (a positive, recorded "N/A on this backend" observation). A signal is **fail-closed/missing** when the producer was *expected* to run and the output key is simply absent or empty. `from_run_output` must never default an **expected** signal to its passing token. The default for an expected-but-absent signal is the **abstaining** token; the not-assessed token is reserved for an *explicit* backend-N/A declaration.

**Critical nuance — why `not_assessed` is non-blocking but `missing` is blocking, given `trustworthy?` hard-requires the good token:** `trustworthy?/1` (trust_score.ex:105-110) hard-requires `calibration==:valid AND baseline==:green AND replay==:none AND integrity=="trustworthy"`. Today `:not_assessed`/`:unknown` would FAIL `trustworthy?` and abstain — that is correct for a *missing* signal but WRONG for a genuinely-not-assessable one (it would park the reference if, say, docker is absent). The taxonomy resolves this per signal:

- **Signals that are always assessable on every backend** (calibration, baseline, integrity-source-mutation, replay-per-slice, provenance): there is no "not-assessable" row — absence is always `missing` → fail-closed. `trustworthy?` keeps hard-requiring the good token. No change needed to `trustworthy?` for these.
- **Signals that can be genuinely backend-N/A** (hermeticity/network under `:local`, replay when no recorded baseline exists yet, corpus on cold start): these must be **excluded from `trustworthy?`** when not-assessable, exactly as `corpus_pass_rate` already is (trust_score.ex:104 comment + :105-110 omits corpus). They contribute 0.5 to the *score* (a soft penalty) but do not hard-block. **The owning sub-stream (B for hermeticity, C for replay/corpus) is responsible for keeping its not-assessable signal OUT of `trustworthy?` and proving the reference still auto-accepts on the backend where the signal is N/A.** A-trust-core owns the *contract*; B/C own their signal's placement.

This sub-stream (A) owns **calibration** and **baseline**, both always-assessable, so for A there is no not-assessable row — absence is always fail-closed. A also wires `from_run_output` to **stop laundering** and to **route** each signal to the right column, providing the helper other sub-streams call.

---

### Slice ordering within A (and the rest of M4 depends on A1 + A6)

```
A1  fail-closed taxonomy + non-laundering from_run_output         (keystone; pure; no producer flip yet)
A2  real BaselineHealth runner + materialize :baseline_regression suites
A3  flip baseline fail-closed  (depends A1, A2)  + re-tune (A6 protocol)
A4  real AcceptanceCalibration runner (kill fabrication)
A5  flip calibration fail-closed (depends A1, A4) + re-tune
A7d dr1m.7 empty-acceptance-suite hard-fail, defense-in-depth (runner suite/3 + VerificationRerunner + gate)
A6  the re-tuning protocol  (reference doc + a reusable test module; consumed by A3, A5, and ALL other sub-streams)
A7  the discrimination-harness pattern (reusable macro/helper; consumed by ALL other sub-streams)
```

`A6` and `A7` are written as **artifacts first** (A1 produces the helper, A6/A7 the protocol+harness) and then *applied* in A3/A5; I describe them as their own sections because other sub-streams import them. Recommended build order: **A1 → A7 (harness) → A6 (protocol skeleton) → A2 → A3 → A4 → A5 → A7d**. A1/A6/A7 must merge first because B, C, D import them.

---

### A1 — Fail-closed taxonomy + non-laundering `from_run_output/1`

**Goal:** `TrustEvidence` stops laundering. Absent **expected** signals route to the abstaining token, not the passing token; an **explicit backend-N/A** observation routes to `:not_assessed`. This is pure (no producer changes yet) and is the keystone other sub-streams import.

**Files + functions to change**

`lib/conveyor/gate/trust_evidence.ex`
- **CURRENT (`from_run_output/1`, :25-33):** reads five raw keys and feeds them to `assemble/1`. **TARGET:** unchanged shape, but it now also threads a `:declared_not_assessable` set (a list under output key `"trust_not_assessable"`, default `[]`) so a producer can *positively* declare "this signal is N/A on this backend." Signals in that set route to `:not_assessed`/`:unknown`; signals NOT in it and absent route to the **abstaining** token.
- **CURRENT (`calibration/1`, :48-49):** `calibration(_status) -> :valid`. **TARGET:** three clauses —
  ```elixir
  defp calibration(status) when status in [:valid, "valid"], do: :valid
  defp calibration(status) when status in [:invalid, "invalid"], do: :invalid
  defp calibration(_absent), do: :not_assessed   # was :valid (the leak)
  ```
  (`:not_assessed` is the abstaining token for calibration: it scores 0.5 AND fails `trustworthy?` because `trustworthy?` requires exactly `:valid`. For an always-assessable signal, not_assessed == fail-closed. We reuse the existing TrustScore atom; no new value needed.)
- **CURRENT (`baseline/1`, :51-52):** `baseline(_status) -> :green`. **TARGET:**
  ```elixir
  defp baseline(status) when status in [:passed, "passed", :green, "green"], do: :green
  defp baseline(status) when status in [:failed, "failed", :red, "red"], do: :red
  defp baseline(_absent), do: :unknown            # was :green (the leak)
  ```
  (`:unknown` scores 0.5 and fails `trustworthy?` which requires `:green`. Note: the station emits `"passed"`/`"failed"` strings, NOT `"green"`/`"red"` — the current code at :51 only recognized `failed/red`; the good string `"passed"` fell through to the catch-all `:green`. After this change `"passed"` must be EXPLICITLY mapped to `:green`, else it would route to `:unknown` and break the reference. **This is a trap: the station's vocabulary is passed/failed, the score's is green/red.**)
- **CURRENT (`integrity/1`, :54-56):** catch-all → `"trustworthy"`. **TARGET — A1 LEAVES the integrity clause LAUNDERED to `"trustworthy"`; the un-laundering is owned by D4, NOT A and NOT B.** A1 does NOT touch `integrity/1`. The integrity catch-all keeps mapping `not_assessed`/`nil → "trustworthy"` until the atomic M4.8 {D4 + C1} commit flips it (D4 changes the catch-all to `"not_assessed"`, co-shipped with C1's first clean probe admission). **A1 changes ONLY the calibration + baseline clauses** (it owns those producers in A2/A4). → **decision baked (CANONICAL — supersedes any "flipped by B" / "flipped by A1" wording elsewhere): the integrity un-laundering is owned by D4 ONLY, co-shipped atomically with C1 (first clean probe admission) in the `{D4 + C1}` commit at M4.8; D3 (docker producer) is a PREREQUISITE landed earlier in M4.7, NOT part of the atomic commit. A1 leaves integrity laundered. B touches replay + corpus, never integrity.**
  > **F13/F21 honesty note (carry into A1's comments + the A6 anchor):** because A1 leaves integrity laundered, the reference's integrity `1.0` through M4.1–M4.7 is **fabricated, not earned** — an auto-accept in this window proves calibration/baseline/replay are real, NOT integrity. Integrity becomes earned only at M4.8 {D4 + C1}. Do not read an early-window green reference as a fully-real one; the `reference_auto_accept_test.exs` anchor's `integrity earned?` column flags this.
- **CURRENT (`replay/1` :58-59, `corpus/1` :61-62):** owned by C. A1 leaves them as-is (C flips them). A1's helper signature supports them.

**New helper (called from A3/A5/B/C/D):**
```elixir
@spec assemble(map()) :: TrustScore.evidence()
# signals may include :declared_not_assessable => [:hermeticity, :replay, ...]
# A signal in that set and otherwise absent routes to its not_assessed token
# (non-blocking middle); a signal absent and NOT in the set routes to its
# abstaining token (fail-closed).
```

**Discrimination test(s)** — `test/conveyor/gate/trust_evidence_test.exs` (extend the existing file)

This is the anti-vacuity core. The existing tests at :45-48 ("empty output is non-blocking (auto-accept)") and :51-59 ("unmeasured signals default to non-blocking") **encode the leak as the spec** — they MUST be rewritten, not merely added to. New tests:

- `test "BROKEN: absent calibration no longer launders to valid — it abstains"` — `band(%{"baseline_health_status" => "passed"})` (calibration key absent) **== :abstain** (was :auto_accept). This is the BROKEN-signal case: the producer didn't run → fail-closed → park.
- `test "BROKEN: absent baseline abstains"` — `band(%{"test_pack_calibration" => %{"status" => "valid"}})` **== :abstain**.
- `test "GOOD: measured-good calibration + measured-good baseline auto-accepts"` — `band(%{"test_pack_calibration" => %{"status" => "valid"}, "baseline_health_status" => "passed"})` **== :auto_accept**. (Proves we didn't over-tighten: the reference's real evidence still accepts. Note the `"passed"` string must map to green.)
- `test "GOOD: declared backend-N/A signal is non-blocking, not fail-closed"` — feed `assemble(%{declared_not_assessable: [:replay]})` and assert `replay_divergence == :unknown` (not `:diverged`); the *other* always-assessable signals absent → still abstain. (This proves the taxonomy split is real: explicit N/A ≠ silent missing.)
- **Anti-vacuity guard test:** `test "from_run_output emits not_assessed for absent always-assessable signals (no laundering)"` — `assert TrustEvidence.from_run_output(%{}).calibration_status == :not_assessed` and `... .baseline_status == :unknown`. This directly kills the laundering and makes the previously-vacuous `trust_score_test.exs:55-65` test reachable through the real path.

**Rewrite/retire:** `trust_evidence_test.exs:45-48` and `:51-59` (the two "unmeasured → non-blocking" tests) are DELETED — they asserted the leak. Replace with the above. Update `assemble/1 defaults` test (:50-59) to assert the *new* defaults (`:not_assessed`, `:unknown`).

**Re-calibration:** A1 does NOT change weights/threshold. But it DOES change what the reference's evidence looks like **only if** the production loop currently omits calibration/baseline keys. **Verify before merging A1:** does the live serial_driver path actually populate `"test_pack_calibration"` and `"baseline_health_status"` in slice output? It does (the stations emit them — `stations/acceptance_calibration.ex:17-25`, `stations/baseline_health.ex:17-22`). So the reference, which *runs those stations*, still emits the good tokens → still auto-accepts. **But** A2/A4 are where those stations become *honest*; A1 alone, with the stations still stubbed, means the stubs emit `:valid`/`:passed` (fabricated) and the reference still accepts. That is acceptable for A1 (incremental: we haven't claimed the producer is real yet). The fail-closed bite arrives in A3/A5 once the real producer can return a *missing* result. **A1 green criterion:** `mix test test/conveyor/gate/trust_evidence_test.exs test/conveyor/gate/trust_score_test.exs --seed 0` green; full `mix test --exclude eval --seed 0` green (the rewrite must not break finalizer/serial_driver tests — search for tests that build slice output with an absent calibration key and currently expect auto-accept; those encode the leak and must be updated).

**br closed:** none fully (A1 is a precondition); it advances dr1m.1.3.

**Risks/traps:**
- **The passed/green vocabulary mismatch (above).** Highest-risk regression: if you forget to map `"passed" -> :green`, the reference abstains and you'll wrongly "re-tune the threshold down" to compensate — masking the bug. The fix is the explicit good-token clause, NOT a threshold change.
- **Grep for every test that constructs slice output without a calibration/baseline key and asserts accept.** Those are leak-encoding tests. Likely culprits: `gate_finalizer_test.exs`, `first_light_production_loop_test.exs`, `recovery_honesty_eval_test.exs`. Each must either supply the good tokens (if the scenario is a genuine pass) or expect abstain (if it was silently relying on the leak).
- **Do not touch `trustworthy?/1` in A1.** Adding/removing clauses there is B/C's job per-signal. A1 only changes the *evidence assembly*.

---

### A2 — Real `BaselineHealth` runner + materialize `:baseline_regression` suites

**Goal:** Kill the first half of the baseline double-vacuity — the station now runs *real* baseline commands via a real runner, and `:baseline_regression` VerificationSuites actually exist for production slices so `baseline_suites/1` is non-empty.

**Files + functions**

`lib/conveyor/stations/baseline_health.ex`
- **CURRENT (:11-22):** `BaselineHealth.run!(run_spec)` — NO runner → default `exit_code: 0` always-pass. **TARGET:** build a real runner from the injected workspace, exactly like `stations/verify.ex:43-50`:
  ```elixir
  def run(input, context) do
    run_spec = run_spec!(context.run_attempt.run_spec_id)
    result = BaselineHealth.run!(run_spec, runner_opts(input))
    {:ok, %{"baseline_health_status" => baseline_status_token(result),
            "baseline_suites" => result.suites}}
  end

  # mirror verify station: a ToolchainRunner-backed closure over the workspace
  defp runner_opts(input) do
    ws = get(input, "workspace_path")
    [runner: fn cmd -> Conveyor.Eval.ToolchainRunner.run_command(ws, cmd, base_opts(input)) end]
  end
  ```
  (Use the existing `ToolchainRunner` command-exec path — `exec/4` at toolchain_runner.ex:178 is invoked by a public `run_command/3`; if no public arity exists, add a thin `@spec run_command(String.t(), map(), keyword()) :: %{exit_code, stdout, stderr}` wrapper that calls the same `exec` the verify station's suite path uses. **Verify the exact public surface before coding — do not duplicate the docker/local branching; reuse it.**)
- **CURRENT status token:** station emits `Atom.to_string(result.status)` = `"passed"`/`"failed"`. **TARGET:** unchanged — but A1 now maps `"passed" -> :green`. Keep the string vocabulary; A1 owns the mapping.

`lib/conveyor/baseline_health.ex`
- **CURRENT (`run!/2` :19-33):** filters `baseline_suites/1`; if empty, `Enum.all?([],…) == true` → `:passed`. **TARGET:** add an explicit **empty-suite policy** parameter so "no baseline suites" is a *taxonomy decision*, not silent pass:
  ```elixir
  def run!(%RunSpec{} = run_spec, opts \\ []) do
    suites = run_spec.slice_id |> baseline_suites() |> Enum.map(&run_suite(&1, opts))
    status =
      cond do
        suites == [] -> Keyword.get(opts, :on_empty, :not_assessed)  # was implicit :passed
        Enum.all?(suites, &(&1["status"] == "passed")) -> :passed
        true -> :failed
      end
    %Result{status: status, suites: suites}
  end
  ```
  **Taxonomy mapping:** `:not_assessed` here = "no baseline suite defined for this slice." Per the taxonomy, baseline is *always-assessable in principle*, but a slice may legitimately have **no baseline regression** (a greenfield slice). So the honest classification is **not-assessable for THIS slice** → non-blocking — NOT fabricated `:passed`. The station emits a new third token; A1's `baseline/1` maps it: add `defp baseline(status) when status in [:not_assessed, "not_assessed"], do: :unknown`. `:unknown` scores 0.5 (soft penalty) and is **excluded from `trustworthy?`** ONLY if baseline becomes a not-assessable signal — **decision: baseline stays in `trustworthy?` (always-assessable); a slice with no baseline suite gets `:unknown` which FAILS `trustworthy?` → abstain.** That is correct fail-closed: a slice claiming a pass with zero baseline coverage should be parked for a human, not auto-merged. **BUT** this would park the reference if the reference slices have no baseline suite — so A2 MUST also materialize the suites (next bullet). **This coupling is why A2 wires the producer AND the suites in one slice.**

**Materialize `:baseline_regression` suites (the other half of the double-vacuity):**
- **CURRENT:** no production code creates `VerificationSuite` rows with `suite_kind: :baseline_regression`. **TARGET:** the contract/run-spec assembly path must create one baseline_regression suite per slice from the plan's verification commands. The cleanest seam: wherever `acceptance_locked` suites are created for a slice (search `Ash.create!(VerificationSuite` and `suite_kind:`), add a sibling `:baseline_regression` suite whose `command_specs` are the plan's baseline/regression commands. For the canary corpus, add the suite to the sample seeds (`SampleTasksSeed`, and the beads/gx equivalents) so the reference slices have baseline coverage. **Verify:** `baseline_acceptance_test.exs:27-51` already creates a `:baseline_regression` suite and runs `BaselineHealth.run!` with a real runner and gets `:passed` — that test is the working contract; A2 makes the *production seed/assembler* create the same row the test creates by hand.
- **CONCRETE baseline_regression command per sample (NOT "e.g. full pytest" — specify it, and prove it is non-vacuous):**
  - `samples/tasks_service`: `python -m pytest tests -q` (the sample's own full unit suite at `samples/tasks_service/tests/`, i.e. workspace-relative `tests/`, distinct from the locked acceptance subset). **NOT `tasks_service/tests` — that path does not exist (verified); the tests live at the sample root's `tests/`.**
  - `samples/beads_insight`: `python -m pytest tests -q` (the full `tests/` dir — `tests/test_loader.py` etc.).
  - `samples/gx`: `python -m pytest tests -q` (the full gx `tests/` dir).
  Each materialized baseline suite MUST run **≥1 real test**. **Anti-vacuity guard (mirrors the dr1m.7 empty-acceptance guard, A7d):** add an assertion that the materialized baseline_regression suite collected `>= 1` test for each reference slice; a baseline suite that runs zero tests is itself a fabrication (the same vacuity A7d kills for acceptance) and must FAIL the materialization, never silently pass. **Greenfield-first-slice honesty:** if a genuinely greenfield first slice has no regression surface yet, the honest result is `on_empty: :not_assessed` → `:unknown` → park-for-human (per A2's `on_empty` policy below), NOT a synthetic always-pass suite. We do NOT manufacture a vacuous baseline suite to dodge a park — a no-baseline slice parks honestly; a slice WITH a baseline must run a real, non-empty regression command.

**Discrimination test(s)** — `test/conveyor/baseline_health_discrimination_test.exs` (new)

- `test "BROKEN: a baseline command that exits non-zero yields :failed -> baseline :red -> abstain"` — create a `:baseline_regression` suite, run `BaselineHealth.run!(run_spec, runner: fn _ -> %{exit_code: 1} end)`; assert `result.status == :failed`; thread through `TrustEvidence.assemble(%{baseline: :failed})` → `TrustScore.evaluate` → **band == :abstain**.
- `test "BROKEN: no baseline suite for the slice -> :not_assessed -> :unknown -> abstain (fail-closed, not fabricated pass)"` — run with zero suites; assert `status == :not_assessed`; assert the full reference-shaped evidence with baseline `:unknown` and everything else good → **band == :abstain**. (This is the kill-shot for the double-vacuity: previously empty → passed → accept.)
- `test "GOOD: green baseline suite -> :passed -> :green -> auto-accept with reference evidence"` — real runner `exit_code: 0`, suite present; full reference evidence → **band == :auto_accept**.
- **Anti-vacuity assertion:** in the BROKEN-empty test, also assert that WITHOUT this fix the old code would have returned `:passed` — encode it as a comment + a direct assertion `refute status == :passed` so a regression that reintroduces the leak fails loudly.

**Re-calibration:** A2 changes no weights. It DOES require that the reference corpus now carries baseline_regression suites (else A3's flip parks them). **Verification step for A2:** run the docker discrimination test path and the gauntlet on the reference; confirm `baseline_health_status == "passed"` for the reference. Since A2's flip-to-fail-closed is deferred to A3, A2 alone stays green even if a sample lacks the suite (status `:not_assessed` → A1 maps to `:unknown` → with the OLD `trustworthy?` the band could already abstain). **Therefore A2 and A3 should land together or A2 must guarantee every reference slice has a baseline suite before merge.** → **decision baked: A2 lands the suites for ALL three sample corpora in the same PR as the runner, verified by re-running the gauntlet/docker reference, so the not_assessed branch never fires for the reference.**

**br closed:** dr1m.1.3 (baseline half).

**Risks/traps:**
- **Looks-wired trap:** the station could "use a runner" but still pass the default closure — re-check that `runner_opts/1` actually threads a `ToolchainRunner` closure, not the inline default. Add a test asserting the station propagates a *real* failure (exit 1) to `:failed`; if the default closure leaks, that test stays green falsely only if you assert via the station's own runner — so assert at the **station** level (build a fake context, inject a workspace whose baseline command fails) not just the core.
- **Workspace availability:** the assembler must inject `workspace_path` to the baseline station (the asymmetry at run_spec_assembler.ex:109-113 gives only `blob_root`). **A2 must also patch the assembler** to add `"workspace_path" => workspace_path` (and `"base_commit"`, `"backend"` if used) to the `"baseline_health"` branch — mirror the implement/verify branches.
- **Don't make baseline not-assessable globally.** Keeping it in `trustworthy?` is the fail-closed choice; if a real greenfield slice legitimately has no baseline, that should *park for a human*, which is correct, not auto-merge.

---

### A3 — Flip baseline fail-closed + re-tune (applies A6 protocol)

**Goal:** With A1 (non-laundering) and A2 (real producer + suites) merged, baseline now fails closed: a missing/red baseline parks. Confirm the reference still auto-accepts; re-tune weights/threshold **only if** the reference's score dropped below 0.9, and only via the A6 protocol.

**Files:** none new — this is the *verification + re-tune* slice. The flip already happened structurally in A1+A2 (`baseline(_absent) -> :unknown`, `on_empty: :not_assessed`). A3 is where we *prove* the reference survives and lock the numbers.

**PRE-FLIP verification (mirrors A4/A5's base-red gate — STOP if unmet):** before A3 flips baseline fail-closed, run the real `BaselineHealth` producer (A2) over each reference slice for all three corpora and RECORD/print the per-slice baseline verdict. A3 may flip ONLY if every reference slice that HAS a baseline_regression suite returns a genuinely-green baseline (the real regression command passes on the reference), AND every reference slice's baseline suite is non-empty (ran ≥1 test, per A2's anti-vacuity guard). If any reference slice's baseline is RED on the reference (a real regression) or its suite is empty (a fabrication), that is a producer/corpus defect to FIX — never lower the threshold to rescue it, never manufacture a passing suite. A no-baseline greenfield slice parks honestly (it is not "fixed" by a synthetic suite). This recorded pre-flip verdict is the analogue of A4's base-red recording.

**Re-calibration protocol (the exact A6 steps, applied here):**
1. **Compute the reference's post-flip score.** Reference evidence after A1/A2: `integrity "trustworthy"` (still laundered until D4), `calibration :valid` (still stub until A4), `baseline :green` (now REAL via A2, verified non-empty + green-on-reference by the pre-flip step), `replay :none` (until B), `corpus nil→0.5`. Score = `0.30 + 0.20 + 0.20 + 0.15 + 0.15*0.5 = 0.925` ≥ 0.9 → **auto_accept unchanged.** No re-tune needed for A3.
2. **Run the three corpora through the real path** (not a hand-built map): `mix test --include eval test/conveyor/eval/integrity_discrimination_docker_test.exs` (beads reference) and the gauntlet known_good for tasks_service + beads. Assert `final.run_attempt.outcome == :accepted` for every reference case.
3. **Only if a reference abstains:** that means baseline legitimately returned `:unknown` for a reference slice → a missing suite (A2 bug, fix the seed) OR the score dropped (impossible here since 0.925 ≥ 0.9). **Never lower the threshold to rescue a reference that abstained for a real reason** — diagnose the producer first.

**Discrimination test:** the new `baseline_health_discrimination_test.exs` from A2 IS the A3 discrimination proof; A3 adds an **end-to-end Finalizer** test mirroring `integrity_discrimination_docker_test.exs` but for baseline:
- `test/conveyor/gate/baseline_abstain_finalizer_test.exs` (new, `:eval`-tagged if it touches docker, else plain DataCase): build a passed gate, thread `trust_evidence` with a red baseline → assert `final.run_attempt.outcome == :abstained` AND `Slice` state `:parked`. The GOOD case (green baseline) → `:accepted`.

**Green criteria:** `mix test --exclude eval --seed 0` green; the new discrimination + finalizer tests green; the docker reference test (`--include eval`) shows reference `:accepted`; `mix conveyor.eval.scorecard --gate` exit 0 (no new blocking metric — baseline doesn't have a scorecard metric yet; if A adds one, see A6).

**br closed:** dr1m.1.3 (baseline fully closed once A2+A3 land).

**Risks/traps:** the only way A3 regresses the reference is a sample lacking a baseline suite (A2 fixed) or a transient real test failure in the reference (which is a *correct* park — investigate, do not suppress).

---

### A4 — Real `AcceptanceCalibration` runner (kill the fabrication)

**Goal:** The single most dangerous stub. Today it **fabricates** `status: :valid` + `expected_failures` without running anything (because the default runner returns exit 1, hitting the false-branch which *manufactures* a valid base-red calibration). Make it run real commands; a calibration is `:valid` ONLY when the locked acceptance tests genuinely RED on base.

**Files + functions**

`lib/conveyor/stations/acceptance_calibration.ex`
- **CURRENT (:11-25):** `AcceptanceCalibration.run!(run_spec, blob_root:)` — NO runner. **TARGET:** inject a real runner over the **base** workspace (calibration runs the locked tests at `base_commit` to confirm they fail before the patch):
  ```elixir
  calibration =
    AcceptanceCalibration.run!(run_spec,
      blob_root: get(input, "blob_root"),
      runner: base_runner(input))   # ToolchainRunner over the base-commit workspace
  ```
  **Important semantic:** calibration is a *base-red* check — the locked tests must be RED at base (proving they actually assert the new behavior). The runner must execute against a **clean base checkout**, not the patched workspace. The assembler must inject `workspace_path` + `base_commit` so the station can materialize the base tree (or the runner closure checks out base). **Verify the base-checkout mechanism the loop already uses** (the implement station gets `base_commit` at run_spec_assembler.ex:118) and reuse it; do not invent a new checkout path.

`lib/conveyor/acceptance_calibration.ex`
- **CURRENT (:25-47, two `calibration_attrs` clauses):** `all_green? == false` → `status: :valid, expected_failures: required_test_refs` (the fabrication); `all_green? == true` → `:invalid`. **The bug:** with the default runner returning exit 1, `all_green?` is always false → always emits `:valid`. With a REAL runner this becomes correct (tests really red → valid; tests really green at base → invalid, meaning they don't assert anything new). **TARGET:** keep the two clauses (the logic is right *given real results*) but add a **third state** for "could not run / no tests":
  ```elixir
  # all_green? is now :all_green | :some_red | :no_tests | :error from a richer run
  ```
  Specifically, if `test_pack.runner_command_specs == []` or the runner returns an infra error, emit `status: :not_assessed` (NOT `:valid`). Per taxonomy: acceptance calibration is always-assessable, so "no locked tests" / "couldn't run" is **fail-closed** → A1's `calibration(_absent) -> :not_assessed` already abstains. The station must emit `status: "not_assessed"` in that case, and A1's `calibration/1` must recognize it: add `defp calibration(status) when status in [:not_assessed, "not_assessed"], do: :not_assessed`.

**Discrimination test(s)** — `test/conveyor/acceptance_calibration_discrimination_test.exs` (new; the existing `baseline_acceptance_test.exs:53-87` already covers valid/invalid with a *real injected runner* — extend, don't duplicate)

- `test "BROKEN: with the real runner, locked tests that PASS on base -> :invalid -> calibration_status :invalid -> abstain"` — `run!(runner: fn _ -> %{exit_code: 0} end)` → `status == :invalid` (tests green on base means they don't assert the new behavior) → `TrustEvidence.assemble(%{calibration: :invalid})` → **abstain**. (This is the case the fabrication HID: the old default never let `all_green?` be true.)
- `test "BROKEN: no locked acceptance tests -> :not_assessed -> abstain (fail-closed, not fabricated valid)"` — a test_pack with empty `runner_command_specs` → `status == :not_assessed`; reference-shaped evidence with calibration `:not_assessed` → **abstain**.
- `test "GOOD: locked tests genuinely RED on base -> :valid -> auto-accept"` — `runner: fn _ -> %{exit_code: 1} end` AND a non-empty test_pack → `status == :valid, expected_failures != []` → with reference evidence → **auto_accept**.
- **Anti-vacuity kill-shot:** `test "the station does NOT fabricate :valid without running (regression guard for the default-runner leak)"` — call the **station** `run/2` (not the core) with a context whose base workspace makes the locked tests *pass* on base; assert the emitted `test_pack_calibration.status == "invalid"`, NOT `"valid"`. If someone reintroduces the no-runner default (exit 1 → fabricated valid), this test fails. This directly targets the fabrication.

**Re-calibration:** none in A4 (the flip is A5). A4 is the PRE-FLIP VERIFICATION COMMIT (no fail-closed flip yet — that is A5). **A4 is its own green commit whose job is to RECORD and PRINT the per-corpus base-red verdict so A5 can gate on it.** With the real runner, A4 makes the reference's calibration *genuinely* `:valid` ONLY IF the reference's locked tests really are red on base.

**Mandatory A4 pre-flip step (the gate on A5):** run A4's real calibration over the BASE checkout for ALL THREE corpora (`samples/beads_insight`, `samples/gx`, `samples/tasks_service`) and record/print the per-corpus result: `{:ok, :valid, expected_failures}` (genuinely red-on-base) vs `{:invalid}` (tests green on base → they assert nothing new) per slice. Add a named test/diagnostic `acceptance_calibration_base_red_test.exs` that asserts and PRINTS each corpus's base-red verdict WITHOUT yet failing the gate closed. **A5 (the flip) may proceed ONLY if all three corpora are genuinely red-on-base.** If any corpus is NOT red-on-base, that is a **reference-corpus defect** (the locked tests don't assert the slice's behavior) → the fix is to **repair the reference's acceptance tests** so they genuinely fail on base — do NOT re-tune, do NOT skip the flip, do NOT revert to fabrication. This "stop and fix the corpus" fork is an explicit possible outcome of A4, not an accident. **This is high-value: A4 tells us whether our reference acceptance tests are actually meaningful or were always rubber-stamped by the fabrication.**

**Green criteria:** `mix test --exclude eval --seed 0` green; new discrimination tests green; reference corpora calibrate to `:valid` (verified via gauntlet/docker reference run); `mix conveyor.eval.scorecard --gate` exit 0.

**br closed:** dr1m.1.3 (calibration half — fully closed with A5).

**Risks/traps:**
- **The biggest trap in M4.** If the reference's locked acceptance tests are NOT actually red on base, A4 will (correctly) make the reference abstain — and the tempting "fix" is to revert to fabrication. DO NOT. The correct fix is to make the reference's locked tests genuinely assert the slice behavior so they fail on base. This is the *point* of the whole exercise. Flag loudly if any reference slice fails this — it means the corpus was vacuous.
- **Base vs. patched workspace.** Calibration MUST run on base, not on the patched tree. If it accidentally runs on the patched tree, the tests pass → `:invalid` → reference abstains. Verify the workspace the runner closes over is the **base** checkout.
- **Empty `runner_command_specs`** must route to `:not_assessed`, not crash and not fabricate.

---

### A5 — Flip calibration fail-closed + re-tune

**Goal:** With A1 + A4 merged, calibration fails closed. Prove the reference survives; re-tune only via A6 if score < 0.9.

**PRECONDITION (the gate from A4 — STOP if unmet):** A5 may land ONLY if A4's recorded base-red verdict is `:valid` (genuinely red-on-base) for ALL THREE corpora. If A4 found any corpus green-on-base, that corpus's locked acceptance tests do not assert the new behavior — fix the reference's locked tests FIRST (a "stop and fix the corpus" fork), then re-run A4's recording, then land A5. Flipping calibration fail-closed while a corpus is green-on-base would (correctly) park that reference → red main. Do NOT flip blind.

**Files:** none new (flip is structural in A1+A4). A5 is the verification + re-tune slice + the end-to-end finalizer test.

**Re-calibration (A6 applied):** post-A5 reference evidence: `integrity "trustworthy"` (laundered until B), `calibration :valid` (REAL via A4), `baseline :green` (REAL via A2), `replay :none` (until C), `corpus nil→0.5`. Score = **0.925** ≥ 0.9 → auto_accept unchanged. No re-tune. Run all three corpora end-to-end; assert `:accepted`.

**Discrimination test:** `test/conveyor/gate/calibration_abstain_finalizer_test.exs` (new) — passed gate + `trust_evidence` with `calibration_status: :invalid` → `:abstained` + `:parked`; GOOD (`:valid`) → `:accepted`.

**Green criteria:** as A3/A4. `mix conveyor.eval.scorecard --gate` exit 0.

**br closed:** **dr1m.1.3 fully closed** (both baseline and calibration now real + fail-closed).

**Risks/traps:** same A4 base-red caveat — if a reference abstains here, it is a corpus problem, not a calibration bug.

---

### A7d — dr1m.7 empty-acceptance-suite hard-fail (defense-in-depth)

**Goal:** An acceptance suite with **zero tests** must FAIL the gate, not pass. Fix at THREE layers (the eval runner, the production rerunner, and the gate stage) so no single producer can re-leak.

**Files + functions**

**Layer 1 — eval runner** `lib/conveyor/eval/toolchain_runner.ex`
- **CURRENT (`suite/3` :332-336):** `failed? = Enum.any?(tests, …)`; `[]` → `false` → `"passed"`. **CURRENT (`verification_result/3` :88-93):** builds `acceptance_tests` with no non-empty check. **TARGET:** an `acceptance_locked` suite with `tests == []` is `"failed"` (or, cleaner, the function emits a finding). Minimal change:
  ```elixir
  defp suite("acceptance_locked", argv, []), do: empty_acceptance_suite(argv)  # status "failed", reason "no acceptance tests ran"
  defp suite(kind, argv, tests), do: ... (existing)
  ```
  (Baseline_regression empty is also suspicious but the production policy for baseline-empty is A2's `:not_assessed`; for acceptance_locked, empty == hard fail because an acceptance suite that asserts nothing is the dr1m.7 false-pass.)

**Layer 2 — production rerunner** `lib/conveyor/evidence/verification_rerunner.ex`
- **CURRENT (:32-37):** `Enum.all?([], …) == true` → `:passed` when NO suites; and a suite whose commands produced zero tests → `command_status` → `"passed"`. **THIS IS THE PRODUCTION LEAK the seed facts did not name.** **TARGET:** mirror Layer 1 — a `suite_kind == "acceptance_locked"` suite that ran zero tests, OR the *absence* of an acceptance_locked suite entirely, must drive `:failed`. Add an explicit assertion:
  ```elixir
  # require a non-empty acceptance_locked suite; absent/empty -> :failed
  ```
  Verify whether the production loop guarantees an acceptance_locked suite exists per slice (it should, post-A2 which materializes suites). If a slice has no acceptance_locked suite, that is fail-closed.

**Layer 3 — gate stage** `lib/conveyor/gate/stages/test_execution.ex`
- **CURRENT (`require_suite/3` :123-129):** presence-only; **`failed_suite_findings` :131-144** treats `"passed"` as fine; nothing checks *non-emptiness*. **TARGET:** add an `empty_acceptance_suite` finding:
  ```elixir
  defp empty_acceptance_findings(suites) do
    suites
    |> Enum.filter(&(value(&1, :suite_kind) == "acceptance_locked"))
    |> Enum.filter(&acceptance_ran_zero_tests?/1)
    |> Enum.map(fn s -> finding("empty_acceptance_suite",
         "Locked acceptance suite ran zero tests — cannot establish a pass.", s) end)
  end
  ```
  Wire it into `findings/3` (:111-121) alongside `require_suite`. `acceptance_ran_zero_tests?/1` inspects the suite's commands→attempts→tests and returns true if the total test count is 0. **This is the backstop: even if Layers 1/2 re-leak, the gate itself rejects a zero-test acceptance suite.**

**Discrimination test(s)** — `test/conveyor/gate/empty_acceptance_suite_test.exs` (new) + extend `mutant_gauntlet`

- `test "BROKEN: acceptance_locked suite with zero tests fails the gate (dr1m.7)"` — feed `test_execution` a `verification_result` whose `acceptance_locked` suite has `commands: [%{attempts: [%{tests: []}]}]`, status falsely `"passed"`; assert the stage status is `:failed` with an `"empty_acceptance_suite"` finding. (BROKEN signal → reject.)
- `test "BROKEN: absent acceptance_locked suite fails the gate"` — suites = only baseline; assert `missing_acceptance_locked` finding (already exists via `require_suite`) makes the stage fail. (Confirms the existing presence check still bites and is not the only defense.)
- `test "GOOD: acceptance_locked with ≥1 passing test passes the stage"` — non-empty tests, all passed → stage `:passed`. (Don't over-reject.)
- **Production-rerunner test:** `test "VerificationRerunner: no acceptance_locked suite -> :failed (not the empty-list pass)"` — a slice with only a baseline suite → `run!` returns `status: :failed`. **Anti-vacuity:** assert `refute result.status == :passed` so the old `Enum.all?([], …)` leak fails the test if reintroduced.
- **Eval-runner test:** extend `mutant_gauntlet_test.exs` — the `test_weakened_or_deleted` mutant (deletes/weakens the acceptance test) should now be caught by `test_execution` as `empty_acceptance_suite` (it is currently in `deferred_static_stage`). **This is high-value:** dr1m.7's fix may *promote* `test_weakened_or_deleted` from static-deferred to behaviorally-caught. Verify the mutant's `expected_catch` and, if appropriate, move it to the behavioral set and assert `false_pass_rate == 0` still holds.

**Re-calibration:** none (dr1m.7 is a gate-stage hard-fail, not a TrustScore weight). It interacts with TrustScore only indirectly: a failed `test_execution` stage makes `passed? == false`, so the Finalizer never reaches the trust path. Verify the reference (which has real, non-empty acceptance suites) still passes `test_execution`.

**Green criteria:** `mix test --exclude eval --seed 0` green; new empty-suite tests green; `mix conveyor.eval.scorecard --gate` exit 0 with `false_pass_rate == 0` (the gauntlet must show the reference passes and no mutant — including any promoted `test_weakened_or_deleted` — false-passes).

**br closed:** **dr1m.7.**

**Risks/traps:**
- **The named-but-incomplete trap:** the seed facts named only `ToolchainRunner.suite/3` and `test_execution`. The PRODUCTION path uses `VerificationRerunner`, which has the identical leak. Fixing only the two named spots leaves production leaky while CI (gauntlet) goes green — the worst kind of false confidence. **Fix all three layers.**
- **Don't reject legitimately-skipped acceptance with an approved waiver.** The existing `allowed_skipped_acceptance_refs` / flake-quarantine machinery exists; an explicitly-waived empty case (rare) should still respect waivers. Default: empty == fail.
- **`passed_with_warning`:** a suite can be `passed_with_warning` (flake). Ensure the empty check looks at *test count*, not status string, so a `passed_with_warning` empty suite is still caught.

---

### A6 — The weight/threshold re-tuning protocol (cross-cutting; consumed by A3, A5, B, C, D)

**Goal:** A single, reusable, *executable* protocol every sub-stream follows when its flip changes the reference's score. It must make it impossible to "re-tune the threshold to rescue a reference that abstained for a real reason."

**Deliverable 1 — the protocol (documented inline + a reference module):** `lib/conveyor/gate/trust_policy.ex` (new, optional but recommended) or, lighter, a documented constant block in `trust_score.ex`. **Recommendation (brake on complexity):** do NOT build a policy-loading subsystem now. Keep weights/threshold as the existing module attributes (`@default_weights`, `@default_thresholds`) and the override `opts`. The protocol is a *process*, encoded as a test, not a new runtime component.

**Deliverable 2 — the reference-survival test module:** `test/conveyor/gate/reference_auto_accept_test.exs` (new, plain ExUnit, no DB) — the **calibration anchor**. It enumerates the reference evidence at the CURRENT M4 stage and asserts auto_accept. It is updated at each flip (A3/A5/B/C/D) to reflect which signals are now real:

```elixir
# The known-good reference MUST auto-accept at every M4 stage. This is the
# loop_integrity invariant. Update the `reference_evidence_stage_N/0` as each
# producer goes real; NEVER lower the threshold to keep this green — fix the
# producer or the corpus instead.
@anchor_score_floor 0.9
test "reference auto-accepts and scores >= threshold (loop_integrity)" do
  r = TrustScore.evaluate(current_reference_evidence())
  assert r.band == :auto_accept
  assert r.score >= r.thresholds.auto_accept
end
```

**The exact anchor table (verified by arithmetic, weights 0.30/0.20/0.20/0.15/0.15, threshold 0.9). The `integrity earned?` column is the F13 honesty flag (see the Section 9 anchor table for the full per-stage version):**

| M4 stage | integrity | calibration | baseline | replay | corpus | **score** | band | integrity earned? |
|---|---|---|---|---|---|---|---|---|
| Today (all laundered) | trustworthy 1.0 | valid 1.0 | green 1.0 | none 1.0 | nil→0.5 | **0.925** | auto_accept | no (laundered) |
| After A2/A3 (baseline real) | 1.0 (laundered) | 1.0 | 1.0 (real) | 1.0 | 0.5 | **0.925** | auto_accept | no (still laundered) |
| After A4/A5 (calibration real) | 1.0 (laundered) | 1.0 (real) | 1.0 | 1.0 | 0.5 | **0.925** | auto_accept | no (still laundered) |
| After B (replay real per-slice) | 1.0 (laundered) | 1.0 | 1.0 | 1.0 (real) | 0.5 | **0.925** | auto_accept | no (still laundered) |
| **At M4.8 {D4 + C1} ATOMIC** (integrity un-laundered + mount_boundary admitted) | 1.0 (real) | 1.0 | 1.0 | 1.0 | 0.5 | **0.925** | auto_accept | **YES (earned @ D4+C1)** |

> **F13 honesty flag:** through every stage BEFORE the atomic M4.8, the reference's integrity 1.0 is **laundered/fabricated, not earned** — an early-window auto-accept proves calibration/baseline/replay are real, NOT integrity. Integrity is earned only at M4.8 {D4 + C1}. The `reference_auto_accept_test.exs` anchor carries this `integrity earned?` column so a laundered green is never misread as a real one.

**The re-tune decision rule (the brake):**
1. Compute the reference score at the new stage. If ≥ 0.9 → **no re-tune.** (A2–A5 all stay at 0.925 — no re-tune for A.)
2. If a flip drops the reference below 0.9, FIRST ask: *did a real producer return a non-good token for the reference?* If yes → that is a real defect (corpus or producer bug) → fix it, do NOT re-tune.
3. Only if the reference's tokens are all genuinely good but the *score* fell below threshold purely because a newly-real signal scores 0.5 (a not-assessable-on-backend signal) → re-tune by **reducing that signal's weight** (redistributing to measured signals) OR **lowering the threshold to the new reference floor minus epsilon**, whichever is more honest. **Record the before/after numbers in the PR body and update the anchor test.** Re-run all three corpora end-to-end.
4. **Forbidden:** lowering the threshold below the level at which a *known mutant* would auto-accept. Cross-check: after any threshold change, re-run the gauntlet and assert `false_pass_rate == 0` — if a re-tune lets a mutant through, it is invalid.

**B-specific note A6 hands to B:** if B makes integrity real and hermeticity is not-assessable on `:local` (docker absent), integrity could score < 1.0 for the reference on the local backend, dropping it below 0.925. B must keep hermeticity OUT of the integrity hard-gate AND ensure the integrity *score* for a clean local run stays high enough (source-mutation assessed-clean), OR run the reference on the docker backend where hermeticity IS assessable. **A6's rule:** B re-tunes only after proving the reference's integrity tokens are genuinely good; the not-assessable hermeticity contributes 0.5 to its sub-component but must not pull the *reference* below 0.9. If it does, reduce integrity's weight or split integrity into (source_mutation, hermeticity) sub-weights — **B's call, A6's rule.**

**Green criteria:** `reference_auto_accept_test.exs` green at every stage; gauntlet `false_pass_rate == 0` after any threshold/weight change.

**br closed:** none directly; it is the safety rail for dr1m.1.3 and the rest of M4.

**Risks/traps:** the entire purpose is to prevent the "rescue the reference by lowering the bar" anti-pattern. The gauntlet cross-check (step 4) is the hard interlock — it makes a too-low threshold *fail CI*.

---

### A7 — The discrimination-harness pattern (reusable; consumed by ALL sub-streams)

**Goal:** One canonical pattern + a small shared helper so every sub-stream's discrimination test proves the gate **fails when it should** (broken signal → abstain/reject), not merely passes when green. This is the anti-vacuity contract for all of M4.

**Deliverable — `test/support/trust_discrimination.ex` (new test helper module):**

```elixir
defmodule Conveyor.Test.TrustDiscrimination do
  @moduledoc """
  Shared discrimination harness (ADR-23 / M4). Every trust signal's test uses
  `assert_discriminates/3` to prove BOTH directions:
    * a BROKEN signal -> :abstain (or the gate stage -> :failed)
    * a GOOD   signal -> :auto_accept (or the gate stage -> :passed)
  A test that asserts only the green direction is VACUOUS and is rejected in review.
  """
  alias Conveyor.Gate.{TrustEvidence, TrustScore}

  @reference %{integrity_verdict: "trustworthy", calibration_status: :valid,
               baseline_status: :green, replay_divergence: :none, corpus_pass_rate: 0.95}

  @doc "The known-good reference evidence (auto-accepts). Override a single signal to break it."
  def reference, do: @reference

  @doc "Assert the reference auto-accepts AND the broken variant abstains."
  def assert_discriminates(broken_override) do
    assert TrustScore.evaluate(reference()).band == :auto_accept
    assert TrustScore.evaluate(Map.merge(reference(), broken_override)).band == :abstain
  end

  @doc "Run a raw slice-output map through the FULL from_run_output -> evaluate path."
  def band_of_output(output),
    do: output |> TrustEvidence.from_run_output() |> TrustScore.evaluate() |> Map.fetch!(:band)
end
```

**The pattern every sub-stream follows (documented in the helper's `@moduledoc` and in `docs/adrs/adr-23-*`):**

> For signal X owned by sub-stream Y:
> 1. **Good case:** the reference (X measured-good) → `:auto_accept` / stage `:passed`.
> 2. **Broken case (REQUIRED):** X set to its measured-bad token → `:abstain` / stage `:failed`.
> 3. **Missing case (REQUIRED for always-assessable signals):** X's output key absent → `from_run_output` emits the abstaining token → `:abstain`. (This is the test that the laundering is gone — it MUST go through `band_of_output`, not a hand-built evidence map, or it is vacuous.)
> 4. **Not-assessable case (only for backend-N/A signals):** X declared N/A → non-blocking → reference still `:auto_accept`.
> 5. **End-to-end (REQUIRED once the producer is real):** through `Finalizer.finalize!` → broken → `run_attempt.outcome == :abstained` AND `Slice` state `:parked`; good → `:accepted`. (Mirror `integrity_discrimination_docker_test.exs`.)

**Anti-vacuity enforcement:** step 3 going through `band_of_output` is the linchpin — it proves the *production assembly path* (`from_run_output`), not just the pure scorer, fails closed. The existing `trust_score_test.exs:55-65` is the cautionary example: it tested the scorer with a not_assessed map the assembler never produced, so it was green while the assembler laundered. Every M4 discrimination test MUST include a `band_of_output(%{...absent...}) == :abstain` assertion for its always-assessable signals.

**Green criteria:** the helper compiles; A1/A2/A4 tests use it; `mix test --exclude eval --seed 0` green.

**br closed:** none directly; it is the anti-vacuity contract for all of M4.

**Risks/traps:**
- **The whole sub-stream exists to defeat this trap:** a discrimination test that only checks the green direction (the current `trust_evidence_test.exs` shape). Reviewers must reject any new trust test lacking a broken-direction assertion through `band_of_output`.
- Keep the helper in `test/support` (compiled only in test env) — do not leak test scaffolding into `lib/`.

---

### Cross-cutting summary for A-trust-core

- **Final hard gate (the A contribution to the M4 exit):** `mix test --exclude eval --seed 0` green; ALL A discrimination tests green (each proves broken→park/reject AND good→accept through the real path); `reference_auto_accept_test.exs` green (reference auto-accepts at score 0.925); `mix conveyor.eval.scorecard --gate` exit 0 with `false_pass_rate == 0` on tasks_service + beads (+ gx where wired); the calibration/baseline/empty-suite stub leaks proven dead by anti-vacuity regression guards.
- **What A hands the rest of M4:** the taxonomy table, `from_run_output` that no longer launders, A6's re-tune protocol + anchor test, A7's discrimination helper. B/C/D import A1's `assemble/1`, A6's `reference_auto_accept_test`, and A7's `assert_discriminates`/`band_of_output`.
- **What A explicitly does NOT do (canonical owners — corrected):** the integrity probes/producer (**C**), hermeticity + docker-abstain + the integrity un-laundering flip D4 (**D**), replay/corpus producers (**B**), provenance/canary/reviewer producers and wiring all 14 stages live and the Finalizer policy_blocked/critical-stop reachability (**E**). A only flips calibration + baseline non-laundering, builds their producers, kills the empty-acceptance leak, and lays the two protocols.
- **Incremental fail-closed honored:** at no slice does the reference park. Score stays 0.925 (≥0.9) through A2–A5 because the laundered-but-not-yet-real signals (integrity, replay, corpus) keep their good/0.5 tokens until their owners flip them — **replay + corpus by B (M4.4), integrity by the atomic `{D4 + C1}` at M4.8 (never by A, B, or C alone)**. A flips a signal fail-closed ONLY in the same slice its real producer lands (baseline in A2/A3, calibration in A4/A5).

---

## Sub-stream B-replay-corpus — `replay_divergence` + `corpus_pass_rate` real producers (dr1m.1.4)

> **One-line charter.** Replace the fabricated `replay_fidelity.status = "matched"` hardcode with a REAL per-slice recorded-vs-replayed digest producer that writes `output["replay_divergence"] => :none | :diverged | :unknown` into the slice output *before* the gate's `TrustEvidence` reads it, plus a `corpus_pass_rate` producer sourced from cassette-corpus fidelity — and flip both signals fail-closed **incrementally**, never parking the known-good reference (`samples/beads_insight` + `samples/gx`).

### Verification of the seed facts (done before designing — all CONFIRMED, with corrections)

I Read every named module/line. Findings:

| Seed claim | Verified? | Note |
|---|---|---|
| `serial_driver.ex:135-152` `replay_report/2` computes a real `replay_digest` but hardcodes `replay_fidelity.status="matched"` | **CONFIRMED** | `:147` literally `"status" => "matched"`. Digest is over `%{schema_version, serial_order, events: normalize_replay_event/1}` (`:136-141`). |
| `normalize_replay_event/1` at `:154-163` keeps `slice_id/sequence/status/gate_result/run_attempt_outcome/findings`, drops db ids/timestamps | **CONFIRMED** | Exactly those 6 keys; `findings` is `Enum.map(&to_string/1)`. This is the surface I must NOT perturb. |
| Merged into run report at `:100`; only consumer is `conveyor.run.ex:72` (human summary); feeds NO gate | **CONFIRMED** | `Map.merge(replay_report(order, events))` at `:100`; `conveyor.run.ex:72` reads `report["replay_fidelity"]` for `summary/1`. Grep shows no `lib` consumer treats it as a gate input. |
| `trust_evidence.ex:30` reads `output["replay_divergence"]`; `:31` reads `output["corpus_pass_rate"]`; NO `lib` code writes either | **CONFIRMED** | `grep -rn "replay_divergence\|corpus_pass_rate" lib` shows only the *consumers* (`trust_evidence.ex`, `trust_score.ex`). Zero producers. |
| **Key mismatch**: driver writes `replay_fidelity` into the *driver report*; TrustEvidence consumes `replay_divergence` from the *slice output* | **CONFIRMED — this is the crux.** | Two different keys in two different maps. `replay_fidelity` (report) is a run-level summary; `replay_divergence` (slice `output`) is the per-slice gate input. They were never connected. My producer fills the gap. |
| TrustScore: `replay_divergence` weight `0.15` AND a HARD auto-accept requirement (`trust_score.ex:105-110` must be `:none`); `:diverged` ⇒ replay component `0.0` AND `trustworthy?/1` false ⇒ band `:abstain` | **CONFIRMED** | `trust_score.ex:109`: `fetch(evidence, :replay_divergence) == :none`. `replay_score/1`: `:none→1.0`, `:unknown→0.5`, `_→0.0` (`:127-129`). **Hard gate**: any non-`:none` replay ⇒ abstain regardless of score. |
| `corpus_pass_rate` weight `0.15` but BOOST-ONLY (excluded from `trustworthy?/1`; cold-start `nil` never abstains — loop_integrity invariant) | **CONFIRMED** | `corpus_score(nil)→0.5` (`:132`); `trustworthy?/1` (`:105-110`) does NOT reference corpus. So corpus only moves the *score*, never the hard gate. |
| Existing comparators to MIRROR: `cassette_bridge.ex:124-148` `replay_corpus/0` (replay each sealed cassette, recompute `result_digest`, `== recorded`, count→fidelity); `replay_engine.ex` `strict_replay_check` (`{:error, reason: :strict_replay_divergence}`); `result_digest` at `:114-116` | **CONFIRMED** | `replay_corpus/0` returns `%{total, matched, fidelity}` and **degrades to `fidelity: 1.0` on an empty corpus** (`:147`). `ReplayEngine.replay(:full,…)` → `:strict_replay_divergence` on tool/event mismatch. |
| `conveyor.run` exits non-zero on `:partial`; `RunSlice.run!/2` `Map.merge`-accumulates station outputs into one `output` map TrustEvidence consumes | **CONFIRMED**, location corrected | `RunSlice` lives at `lib/conveyor/run_slice.ex` (seed said `run_slice.ex:41-53`; the `Enum.reduce_while` accumulation is `run_slice.ex:41-59`, `Map.merge(output, station_output)` at `:53`). `conveyor.run.ex:84`: `:partial → :deterministic_gate_failed`. |
| `serial_driver.ex:492` is where trust_evidence is computed | **CONFIRMED + REFINED** | `:492` is `trust_evidence: trust_evidence(slice_result)` inside `default_finalize_gate!/5`. `trust_evidence/1` (`:505-508`) calls `TrustEvidence.from_run_output(slice_result.output)`. **So my per-slice `replay_divergence` must be merged into `slice_result.output` before `finalize_gate!` runs** — i.e. between `run_slice!` (`:199`) and `finalize_gate!` (`:201`) in `run_one_single_attempt!`, AND in the rework path's injected `run_slice` closure (`:229`). |

**Two corrections / sharpenings the seed under-stated (carry forward):**

1. **The seed conflates two different "replay" notions.** `replay_digest`/`replay_fidelity` (report, run-level, computed in `replay_report/2` at the *end* of the run from all events) is a *reproducibility* digest — the m1/m2/m3/first_light tests assert `result.report["replay_digest"] == replay.report["replay_digest"]` across two clean runs. The **gate** input is `output["replay_divergence"]`, *per-slice*, computed *during* the slice before the gate finalizer. **These are independent.** My slice (B1) builds the per-slice gate producer; the report-level digest hardcode (B3) is a separate, smaller fix (honesty of the human-summary field). I must not entangle them or the determinism tests flap.

2. **Cassettes are gitignored** (`eval/cassettes/.gitignore` = `*.json`), so the corpus is **EMPTY in fresh CI** until an eval test records one. `replay_corpus/0` returns `fidelity: 1.0` on empty (`cassette_bridge.ex:147`). This is load-bearing for the `corpus_pass_rate` producer: an empty corpus must NOT block (it's the BOOST-only signal, so `nil`/`1.0` are both safe), and the discrimination test must seed at least one cassette to prove the path is real, not vacuously-empty-passing.

---

### The central trap of this sub-stream (read before writing any code)

`trust_score.ex:105-110` `trustworthy?/1` makes `replay_divergence == :none` a **HARD requirement for auto-accept**. The replay component weight (0.15) is almost a red herring — the *hard gate* is what bites. Consequences:

- **`:diverged` ⇒ band `:abstain` ALWAYS** (this is what we want for a broken signal). Good.
- **`:unknown` ⇒ band `:abstain` ALWAYS** (because `:unknown != :none`). This is the trap: if the first-ever run of the known-good reference emits `:unknown` (no baseline to compare against yet), it ABSTAINS — **violating loop_integrity and parking the reference.** That is exactly the forbidden "day-one cliff."

**Resolution — the principled taxonomy for THIS signal (baked decision, see `decisions_baked`):**

| Situation | Status | Rationale | Band effect |
|---|---|---|---|
| No baseline recorded yet for this slice (first run) — we ARE the baseline | `:none` | There is nothing to diverge *from*. Recording a baseline is not a divergence; a first observation is trustworthy-by-construction (it is what every later run is checked against). Emitting `:diverged`/`:unknown` here would be a fabricated negative — the mirror-image sin of the old fabricated `"matched"`. | non-blocking (auto-accept eligible) |
| Baseline exists, replayed digest **matches** | `:none` | Genuine match — the real signal we never had. | non-blocking |
| Baseline exists, replayed digest **differs** | `:diverged` | Real recorded-vs-replayed divergence — the slice is non-reproducible. **Fail-closed.** | **abstain (hard)** |
| The slice's output has no normalizable replay shape (e.g. a skipped/parked slice with no station output, or a shape the normalizer can't fingerprint) | `:unknown` | "Should be measurable but the producer couldn't fingerprint it" → conservative fail-closed, distinct from "not applicable." | **abstain (hard)** — but see B1 note: this case never arises for an *accepted* slice in the known-good reference, so it does not park the reference. |

This taxonomy is the difference between **fail-OPEN** (today: everything launders to `:none`) and **fail-CLOSED-but-not-stupid** (M4: divergence and unfingerprintable-shapes abstain, but a legitimate first observation does not). It directly satisfies RATIFIED DECISION #2's taxonomy clause ("'genuinely not assessable' → not_assessed/NON-blocking … distinct from 'should be measured but the producer is missing' → fail-closed/abstain").

> **Anti-vacuity warning (looks-wired-but-vacuous trap inherited from seed + amplified):** It is trivially easy to write a producer that *always* returns `:none` (e.g. baseline lookup silently fails → "no baseline" → `:none`). That reproduces the original bug with extra steps. **Every discrimination test below MUST prove the producer returns `:diverged` (→ abstain/park) on a mutated baseline, not merely `:none` on a clean run.** A test that only asserts a clean run accepts is worthless here. The existing `m1_codex_production_loop_test.exs:60-66` is exactly such a worthless-for-this-purpose test (it asserts digest *equality* across two clean runs — proves reproducibility, proves NOTHING about divergence detection). B1 adds the missing falsifier.

---

### Dependencies & ordering

- **Depends on:** none (this sub-stream is self-contained; it reads/writes the slice `output` map and the gate evidence path that already exist). It does NOT depend on the hermeticity, provenance, canary, or reviewer sub-streams.
- **Other sub-streams that depend on ME:** the re-calibration sub-stream (`A-recalibration` / whoever owns the TrustScore weight-and-threshold re-tune ledger) consumes my flip of `replay_divergence` to fail-closed. I keep my re-tune self-contained (each slice states the exact before/after numbers and re-verifies the reference) so the calibration owner can fold my numbers into the global ledger without re-deriving them. If a separate sub-stream owns `samples/gx` fixtures, B1's gx discrimination test depends on that fixture existing (flagged in `open_for_robert`).
- **Internal ordering (strict):** **B1 → B2 → B3 → B4.** B1 is the load-bearing fail-closed flip and must land first (with its falsifier). B2 (corpus) is BOOST-only and lower-risk. B3 is the honesty cleanup of the report field. B4 is the genome-rate upgrade flag (no code — a tracked follow-on).

---

## Slices

### B1 — Real per-slice `replay_divergence` producer + recorded baseline store (the fail-closed flip)

**Goal.** Compute a real per-slice recorded-vs-replayed digest, persist a baseline on first observation, and write `output["replay_divergence"] => :none | :diverged | :unknown` into the slice output *before* the gate finalizer reads it — so a mutated/non-reproducible slice abstains and parks, while a clean first run and a clean replay both auto-accept.

#### New module — `Conveyor.Replay.SliceDivergence`

- **File:** `lib/conveyor/replay/slice_divergence.ex`
- **Responsibility:** Pure-ish fingerprint of a single slice's reproducible surface + a divergence verdict against a persisted baseline. Mirrors the *shape* of `cassette_bridge.ex` `result_digest` (a `CanonicalJson.digest` over normalized reportable fields) but does **not** couple to the cassette/eval path (RATIFIED #4 layering: production loop must not depend on the eval cassette corpus). It re-uses the SAME normalization logic the driver already trusts.
- **Key signatures (Elixir typespecs):**

```elixir
defmodule Conveyor.Replay.SliceDivergence do
  @moduledoc """
  Per-slice recorded-vs-replayed digest producer for the trust gate (dr1m.1.4).

  Replaces the fabricated `replay_fidelity.status = "matched"` driver hardcode with
  a REAL signal: fingerprint a slice's reproducible surface, compare it to a
  persisted baseline, and emit :none (match / first-observation), :diverged
  (recorded != replayed — fail-closed), or :unknown (unfingerprintable shape —
  fail-closed). First observation is :none by construction (nothing to diverge
  from); recording a baseline is not a divergence.

  Determinism boundary: a conductor-side computation over recorded slice output +
  the persisted baseline. No agent input, clock, or RNG enters the verdict. The
  digest reuses the driver's `normalize_replay_event/1` field set so it cannot drift
  from the run-level replay_digest surface (the 4 cross-run-determinism tests).
  """

  @type status :: :none | :diverged | :unknown
  @type fingerprint :: String.t()  # "sha256:…"

  @doc """
  Fingerprint the reproducible surface of one slice event + its station output.
  Returns {:ok, fingerprint} or :unfingerprintable (no normalizable shape).
  """
  @spec fingerprint(event :: map(), output :: map()) :: {:ok, fingerprint()} | :unfingerprintable

  @doc """
  Verdict for `slice_id` given the freshly-observed fingerprint, using `store`
  (a Conveyor.Replay.BaselineStore impl). On miss: record the baseline, return :none.
  On hit + match: :none. On hit + mismatch: :diverged.
  """
  @spec verdict(slice_id :: String.t(), fingerprint :: {:ok, fingerprint()} | :unfingerprintable,
                store :: module() | {module(), keyword()}) :: status()
end
```

- **Fingerprint surface (CRITICAL — reuse, do not re-invent):** `fingerprint/2` must digest the SAME field set as `serial_driver.ex` `normalize_replay_event/1` (`:154-163`): `slice_id, sequence, status, gate_result, run_attempt_outcome, findings`. **Refactor decision:** extract `normalize_replay_event/1` from `serial_driver.ex` into `Conveyor.Replay.EventNormalizer.normalize/1` (new module `lib/conveyor/replay/event_normalizer.ex`) and have BOTH the driver's `replay_report/2` AND `SliceDivergence.fingerprint/2` call it. This guarantees the per-slice gate fingerprint and the run-level reproducibility digest can never silently diverge — and PRESERVES the surface, so the 4 cross-run-determinism tests (m1/m2/m3/first_light) do not flap (their digests are byte-identical because the normalizer is byte-identical). The fingerprint additionally folds in the slice's relevant station output keys (the calibration/baseline/integrity signals) so a slice that produces *different station output* on replay is caught — `CanonicalJson.digest(%{"event" => EventNormalizer.normalize(event), "output" => reproducible_output(output)})`. `reproducible_output/1` whitelists the deterministic keys (`test_pack_calibration`, `baseline_health_status`, `integrity_verdict`) and drops anything timestamp/id-shaped. `:unfingerprintable` ⇒ when the event has no `slice_id` or `status` (a degenerate/empty event).

#### New module — `Conveyor.Replay.BaselineStore` + `Conveyor.Replay.BaselineStore.File`

- **File:** `lib/conveyor/replay/baseline_store.ex` (behaviour) + `lib/conveyor/replay/baseline_store/file.ex` (default impl).
- **Responsibility:** Persist `{run_key, slice_id} => fingerprint` so a *later* run of the same slice can be checked against the *recorded* one. Production loop = filesystem-backed (DB-free, mirrors the cassette store layering). **Decision (CORRECTED — NOT `priv/`):** baselines live under a **writable runtime location**, defaulting to a workspace-scoped **`.conveyor/replay_baselines/<run_key>/<slice_id>.json`** (per-checkout, not packaged into releases), or a configured data dir (`config :conveyor, :replay_baseline_root`). **Do NOT default to `priv/replay_baselines/`** — `priv/` is packaged into releases and is typically READ-ONLY in a deployed artifact, so per-run writes there fail in any non-dev deploy and silently degrade every run to a "first observation" (`:none`), re-creating the exact always-`:none` vacuity this slice exists to kill. `run_key` defaults to the plan's `contract_sha256` (stable across reruns of the same plan) — injectable. **Guard (mandatory):** an unwritable or missing baseline store must RAISE (or force `:unknown`/fail-closed), NEVER silently return `:miss → :none` — otherwise an unwritable store re-launders to "first observation" forever. Add a `baseline_store_writable?` check at store-open that fails loudly.
- **Behaviour callbacks:**

```elixir
defmodule Conveyor.Replay.BaselineStore do
  @callback fetch(run_key :: String.t(), slice_id :: String.t()) ::
              {:ok, fingerprint :: String.t()} | :miss
  @callback put(run_key :: String.t(), slice_id :: String.t(), fingerprint :: String.t()) :: :ok
end
```

- **Why a behaviour:** the discrimination test (below) injects an in-memory store pre-seeded with a *mutated* baseline to force `:diverged` deterministically with $0 and no filesystem flake. Tests also inject an empty store to assert the first-observation `:none` path.

#### Wiring into the driver (the exact edits)

- **File:** `lib/conveyor/planning/serial_driver.ex`
- **Edit 1 — extract the normalizer (no behavior change):** move `normalize_replay_event/1` (`:154-163`) body into `Conveyor.Replay.EventNormalizer.normalize/1`; replace the driver's `Enum.map(events, &normalize_replay_event/1)` (`:140`) with `Enum.map(events, &EventNormalizer.normalize/1)`. *Current behavior:* private fn in driver. *Target:* delegates to shared module; byte-identical output.
- **Edit 2 — compute & inject per-slice divergence before the gate.** In `run_one_single_attempt!/5` (`:198-218`):
  - *Current (`:199-201`):*
    ```elixir
    slice_result = run_slice!(run_attempt, opts)
    gate = run_gate!(run_spec, run_attempt, slice_result, opts)
    finalization = finalize_gate!(gate, run_spec, run_attempt, slice_result, opts)
    ```
  - *Target:*
    ```elixir
    slice_result = run_slice!(run_attempt, opts)
    slice_result = inject_replay_divergence(slice_result, slice_key, sequence, opts)
    gate = run_gate!(run_spec, run_attempt, slice_result, opts)
    finalization = finalize_gate!(gate, run_spec, run_attempt, slice_result, opts)
    ```
  - New private fn:
    ```elixir
    # dr1m.1.4 — write the REAL per-slice replay_divergence into the slice output the
    # gate's TrustEvidence reads (serial_driver.ex:492 -> from_run_output/1). Injectable
    # store + run_key so tests can force :none/:diverged deterministically ($0).
    defp inject_replay_divergence(%{output: output} = slice_result, slice_key, sequence, opts)
         when is_map(output) do
      event = preliminary_event(slice_key, sequence, slice_result)  # the same 6-field shape
      store = Keyword.get(opts, :replay_baseline_store, Conveyor.Replay.BaselineStore.File)
      run_key = Keyword.get(opts, :replay_run_key, default_run_key(opts))
      status = SliceDivergence.verdict(slice_key, SliceDivergence.fingerprint(event, output), {store, run_key: run_key})
      %{slice_result | output: Map.put(output, "replay_divergence", status)}
    end
    defp inject_replay_divergence(slice_result, _k, _s, _opts), do: slice_result
    ```
  - `preliminary_event/3` builds the `{slice_id, sequence, status, gate_result, run_attempt_outcome, findings}` shape from `slice_result` *as known pre-gate* — i.e. it fingerprints the run-attempt outcome and station output, which is exactly the reproducible surface. (The full post-gate `event` includes gate findings; but the gate hasn't run yet here. **Decision:** fingerprint the PRE-gate surface — the agent/station output — because that is what determines reproducibility; the gate verdict is a deterministic function of it and would be redundant. This avoids a chicken-and-egg where the fingerprint depends on the gate that depends on the fingerprint.)
- **Edit 3 — rework path.** In `run_one_with_rework!/5` the slice runs via the injected `run_slice` closure (`:229`). Wrap that closure so the divergence is injected on the *final accepted attempt's* output before `AttemptLoop` finalizes. **Decision:** inject inside the closure's return so every attempt's output carries `replay_divergence`; the last attempt's output is what the finalizer scores. Concretely change `:229`:
  - *Current:* `|> Keyword.put(:run_slice, fn attempt -> run_slice!(attempt, opts) end)`
  - *Target:* `|> Keyword.put(:run_slice, fn attempt -> attempt |> run_slice!(opts) |> inject_replay_divergence(slice_key, sequence, opts) end)`
- **Edit 4 — TrustEvidence: map unknown SHAPES to `:unknown`, not `:none`.**
  - **File:** `lib/conveyor/gate/trust_evidence.ex`, `replay/1` (`:58-59`).
  - *Current:*
    ```elixir
    defp replay(divergence) when divergence in [:diverged, "diverged"], do: :diverged
    defp replay(_divergence), do: :none
    ```
  - *Target:*
    ```elixir
    defp replay(divergence) when divergence in [:diverged, "diverged"], do: :diverged
    defp replay(divergence) when divergence in [:unknown, "unknown"], do: :unknown
    defp replay(divergence) when divergence in [:none, "none"], do: :none
    defp replay(nil), do: :none          # signal genuinely absent (no producer ran) -> non-blocking, staged-rollout default
    defp replay(_other), do: :unknown    # an UNRECOGNIZED shape is fail-closed, not laundered to :none
    ```
  - *Rationale & taxonomy:* `nil` (the producer didn't run at all — e.g. a unit-test slice with a map-fake output) stays `:none` to preserve the staged-rollout "absent = non-blocking" contract and keep the existing `trust_evidence_test.exs` green (`assemble(%{})` must still yield `replay_divergence: :none`, see `:52-58`). But a *present-but-unrecognized* value (`"weird"`) now becomes `:unknown` (fail-closed) instead of silently `:none` (fail-open). This is the precise "stop laundering unknown shapes" the seed requires, without breaking the documented absent-is-non-blocking default. **This boundary — `nil` vs an unrecognized non-nil — is the single most subtle correctness point in the whole sub-stream; the discrimination test pins it.**

#### The discrimination test(s)

- **File:** `test/conveyor/replay/slice_divergence_test.exs` (new, pure, `async: true`, `mix test --exclude eval --seed 0` covered — NO `:eval` tag).
- **Tests (each names the BROKEN-signal case + expected park/abstain, AND the GOOD-signal case + expected accept):**

  1. `"first observation records a baseline and returns :none (no fabricated negative)"` — empty in-memory store; `verdict/3` returns `:none`; assert the store now has the fingerprint (`put` happened). **GOOD-signal path; expected ACCEPT-eligible.** Guards against fail-closed-on-cold-start (the loop_integrity trap).
  2. `"a clean replay against a matching baseline returns :none"` — store pre-seeded with the SAME fingerprint the slice produces; `verdict/3` returns `:none`. **GOOD-signal; ACCEPT.**
  3. **`"a mutated baseline yields :diverged"`** — store pre-seeded with a DIFFERENT fingerprint (`"sha256:tampered"`); `verdict/3` returns `:diverged`. **BROKEN-signal; the falsifier.** This is the test the codebase has never had.
  4. `"an unfingerprintable (empty) event yields :unknown"` — `fingerprint(%{}, %{})` is `:unfingerprintable` ⇒ `verdict/3` returns `:unknown`. **BROKEN-signal; fail-closed.**

- **File:** `test/conveyor/gate/trust_evidence_test.exs` (extend existing — keeps the suite the gate's evidence contract).
  - Add `"a diverged replay signal in the output abstains"`: `band(%{"test_pack_calibration"=>%{"status"=>"valid"}, "baseline_health_status"=>"passed", "replay_divergence"=>:diverged}) == :abstain`. **BROKEN→abstain.**
  - Add `"an unknown replay signal in the output abstains"`: same with `"replay_divergence"=>:unknown` ⇒ `:abstain`. **BROKEN→abstain.**
  - Add `"an unrecognized replay shape is fail-closed (:unknown -> abstain), not laundered"`: `"replay_divergence"=>"weird"` ⇒ `:abstain`. **Pins the laundering boundary.**
  - Add `"an absent replay signal is non-blocking (auto-accept)"`: `band(%{"test_pack_calibration"=>%{"status"=>"valid"},"baseline_health_status"=>"passed"})` (no `replay_divergence` key) `== :auto_accept`. **GOOD/absent→accept.** (This already implicitly holds via `assemble(%{})`; assert it explicitly so the `nil→:none` clause cannot regress.)

- **File:** `test/conveyor/m1_codex_production_loop_test.exs` (the `:eval` end-to-end falsifier — the integration-level proof).
  - Existing test asserts digest equality across two clean runs (`:60-66`). **Add a third, injected-store sub-assertion** (no live Codex; deterministic, $0): run the loop a third time with `replay_baseline_store:` a store pre-seeded with a *tampered* fingerprint for `SLICE-002`. Assert that `SLICE-002`'s event `status == "parked"` (it abstained) while sibling slices passed — i.e. **divergence on one slice parks exactly that slice, end-to-end through the real gate finalizer.** This is the integration-level anti-vacuity proof that the wiring (`output → TrustEvidence → TrustScore → Finalizer → Slice :parked`) is live, not just unit-green. Tag stays `:eval` (it reuses the recorded-Codex fixture path).
- **PRE-FLIP FINGERPRINTABILITY ASSERTION (the precondition for "stays green" — F17):** before B1's fail-closed flip lands, run `SliceDivergence.fingerprint/2` over EVERY reference slice's real output for BOTH `samples/beads_insight` and `samples/gx` and assert `{:ok, _}` (never `:unfingerprintable`) for each. The flip's green-at-every-commit claim rests on every reference slice routing to `:none` (first observation) and NOT to `:unknown` (which would abstain). If any reference slice produces a degenerate/empty/unfingerprintable shape, it routes to `:unknown` → parks → B1 red. Make this a NAMED test in the reference auto-accept proof so a future reference slice that produces a degenerate shape fails loudly at the producer, not silently at the gate. Without this assertion, "Touches re-tune? No" is true but "stays green" is unverified.

#### Re-calibration (this slice flips `replay_divergence` fail-closed — state the numbers)

- **Weights/threshold BEFORE and AFTER:** **UNCHANGED.** `@default_weights = %{integrity: 0.30, calibration: 0.20, baseline: 0.20, replay: 0.15, corpus: 0.15}`, `@default_thresholds = %{auto_accept: 0.9}` stay exactly as-is. **No re-tune is required for B1** — and that is the point of the taxonomy: the known-good reference's per-slice replay is `:none` (first run records a baseline; the replay run matches it), so `trustworthy?/1`'s `replay_divergence == :none` clause is satisfied and the reference still auto-accepts with the *same* score.
  - **Reference math (verified, `python3`):** reference evidence `integrity=trustworthy, calibration=valid, baseline=green, replay=:none, corpus=0.95` ⇒ score `= 0.30·1 + 0.20·1 + 0.20·1 + 0.15·1 + 0.15·0.95 = 0.9925 ≥ 0.9` ⇒ `:auto_accept`. With `corpus=nil` (cold start, `corpus_score→0.5`) ⇒ `0.925 ≥ 0.9` ⇒ still `:auto_accept`. The replay flip does not move either number because `:none → 1.0` was already the laundered value; the difference is now it's EARNED, not fabricated.
- **How I verified the known-good reference still auto-accepts:** (a) unit — `trust_score_test.exs` `reference_evidence/0` keeps `replay_divergence: :none` ⇒ `loop_integrity invariant` test stays green; (b) evidence — `trust_evidence_test.exs` "empty/unmeasured output is non-blocking (auto-accept)" stays green because `nil → :none`; (c) integration — `m1_codex_production_loop_test.exs` clean run still `:passed` with all events `run_attempt_outcome == :accepted` (the injected-tampered third run is the ONLY one that parks). If ANY of (a)/(b)/(c) goes red, the flip is mis-taxonomized — STOP and re-derive, do not loosen the threshold to paper over it.

#### Green criteria

- `mix test --exclude eval --seed 0` green, including the new `slice_divergence_test.exs` (4 tests) and the 4 added `trust_evidence_test.exs` assertions.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` clean.
- `:eval` run: `mix test --only eval` green, including the new tampered-third-run sub-assertion in `m1_codex_production_loop_test.exs` (proves end-to-end park-on-divergence).
- The 4 cross-run-determinism tests (m1/m2/m3/first_light `replay_digest` equality) UNCHANGED-green (the normalizer extraction is byte-identical).
- `mix conveyor.eval.scorecard --gate`: unaffected by B1 (B1 adds no scorecard metric); must still exit 0.

#### br issues closed

- **`software-factory-ai-dr1m.1.4`** — closed by B1 (the hardcode is replaced by a real comparison; the false trust input is gone). B3 additionally fixes the *report-field* honesty (the human-summary `replay_fidelity.status`), completing the issue's "either real comparison or honest :not_assessed" remediation.

#### Risks / traps

- **(inherited) Vacuous `:none` everywhere.** If `BaselineStore.File.fetch` swallows a read error as `:miss`, every run looks like a "first observation" and never diverges. **Mitigation:** `:miss` is ONLY a genuine "file absent"; an unreadable/corrupt baseline file must raise (or return `:unknown`-forcing), never silently `:miss`. Test 3 (mutated baseline) is the guard; add a "corrupt baseline file" test asserting it does NOT silently pass.
- **The `nil` vs unrecognized boundary in `replay/1`.** Get it backwards and either (a) the staged-rollout default breaks (absent becomes fail-closed → reference parks) or (b) laundering persists (unrecognized becomes `:none`). The 2 added `trust_evidence_test.exs` assertions pin both sides.
- **Run-key collision.** If `run_key` is too coarse (e.g. constant), two *different* plans' same-named slice (`SLICE-001`) collide and produce spurious `:diverged`. **Mitigation:** default `run_key = contract_sha256` (plan-scoped); test the file store keys on `{run_key, slice_id}`.
- **Determinism-test flap.** If the normalizer extraction changes field order or `to_string` behavior, the 4 `replay_digest` tests flap. **Mitigation:** the extraction is a literal move; assert byte-equality of `EventNormalizer.normalize/1` vs the old body in a one-off characterization test, then delete it.
- **Rework path double-injection (REVISED — record/compare on the FINAL accepted attempt, NOT first-write-wins on attempt 1).** Injecting inside the rework `run_slice` closure means EVERY attempt gets a `replay_divergence`. But replay-divergence is a CROSS-RUN reproducibility signal (run the same plan twice, get the same reproducible surface) — it is NOT about intra-run rework attempts. Recording attempt 1's fingerprint and comparing attempt 2 against it conflates the two: rework deliberately changes the agent output, so if a whitelisted signal differs across attempts, attempt 2 would `:diverged` → fail `trustworthy?` → **park a legitimate recovery** — and rework is ON by default (`serial_driver.ex:262`). **Decision (corrected):** within a single run, SKIP intra-run cross-attempt comparison; record the baseline ONCE per `{run_key, slice_id}` from the **FINAL accepted attempt's** fingerprint (the canonical reproducible surface for that slice), to be compared by the NEXT run of the same plan. Concretely: inject `replay_divergence` on the rework loop's *accepted result*, not inside the every-attempt closure. **Severity note:** with B1's narrow whitelist (`test_pack_calibration`/`baseline_health_status`/`integrity_verdict` — all base-relative or process-level, none flips merely because buggy code was fixed) a failed→fixed rework usually does NOT change the fingerprint, so the spurious park is an edge case — but the intra-run/cross-run conflation is a real design error and must be removed; add a discrimination test driving a real 2-attempt rework→accept slice through the injector and asserting it **ACCEPTS**.
- **(NEW — surfaced in review) Replay is structurally vacuous in CI and laundered on cold start, and this is LOAD-BEARING. (Four-part finding; see Open Decision 19 + the §9 REPLAY EARNED note.)**
  1. **Narrow surface (correct, but narrow):** the whitelist deliberately excludes the agent's patch AND `verification_result` — correct, because Codex is stochastic, so including the patch would `:diverged` on every live cross-run and park everything. But what's left (`baseline_health_status` / `test_pack_calibration` / `integrity_verdict`) is base-relative or process-level and therefore IDENTICAL across two clean runs of the same frozen `base_commit` + contract → `:none`. Replay fires `:diverged` ONLY on FLAKY scaffolding (a flaky base regression suite / flaky locked-calibration / an integrity-process flip), NEVER on a divergent agent implementation.
  2. **CI structural inertness:** the `BaselineStore` is per-checkout and empty on a fresh CI clone, so EVERY slice in CI is a "first observation" → records → `:none`, with no second observation to compare against. `:diverged` is therefore UNREACHABLE in CI except via a hand-injected store (test-3 / the m1_codex tampered third run) — which violates A7 ("the BROKEN case must go through the real producer, not a hand-built map").
  3. **First-observation → `:none` is laundering by §6's own taxonomy:** a first observation genuinely *cannot* assess reproducibility (no baseline), so by the keystone rule it is **not-assessable** (`:unknown`/0.5, non-blocking), NOT measured-good (`:none`/1.0). B1 maps it to `:none` and rationalizes it as "trustworthy-by-construction" (above) — the same defense the OLD code could have made for `not_assessed → "trustworthy"`.
  4. **Load-bearing:** this laundering is the ONLY reason the §9 "0.925 at every stage / no re-tune" headline holds — honest not-assessable (0.5) makes cold-start `0.30 + 0.20 + 0.20 + 0.15·0.5 + 0.15·0.5 = 0.85 < 0.9` → the reference PARKS → a real re-tune is forced.
  **Fixes (pick per Open Decision 19):** (a) demote replay to *not-assessable-without-a-baseline* — excluded from `trustworthy?`, scored 0.5/boost when no baseline exists, a HARD `:none`-required gate ONLY once a baseline exists — and own the cold-start re-tune (lower `auto_accept` to ~0.85 or reweight, recorded against the reference); OR (b) keep first-observation → `:none` but add a `replay earned?` honesty flag, drop the unconditional "no re-tune" claim, and decide a store-persistence model so the signal can ever discriminate (commit a per-plan baseline / CI cache keyed on `contract_sha256` / accept replay only discriminates in the live cross-run path on a durable box). EITHER WAY: add a discrimination test that fires `:diverged` through the REAL producer + REAL store (e.g. a base test flaky-red on run 2); if none can be constructed, that is itself proof replay is too narrow to be a hard gate. Reframe B1's claim accordingly — it catches non-deterministic *scaffolding* across runs of the same base, NOT a "mutated/non-reproducible" agent output.

---

### B2 — `corpus_pass_rate` producer from cassette-corpus fidelity (BOOST-only, fail-OPEN by design)

**Goal.** Source `output["corpus_pass_rate"]` from the real cassette-corpus fidelity (`CassetteBridge.replay_corpus/0`) so the score reflects the flywheel's actual replay health — while keeping it BOOST-only (never a hard gate), so an empty/cold corpus can never park the reference.

> **Posture note (important):** `corpus_pass_rate` is **intentionally excluded from `trustworthy?/1`** (`trust_score.ex:105-110`). It is the ONE signal in this whole M4 that **stays fail-OPEN** — and correctly so: it is the cold-start loop_integrity invariant. So B2 does NOT "flip a signal fail-closed." It replaces a *missing* producer with a *real* boost. RATIFIED DECISION #2's fail-closed posture applies to *assessable hard signals*; `corpus_pass_rate` is by-design a boost. I flag this explicitly so a reviewer doesn't mistake the absence of a fail-closed flip here for an oversight.

#### New module — `Conveyor.Replay.CorpusPassRate`

- **File:** `lib/conveyor/replay/corpus_pass_rate.ex`
- **Responsibility:** Compute a `float() | nil` corpus pass rate for a slice run, sourced from cassette fidelity, WITHOUT coupling the production loop to the eval path at call-time. **Decision (layering):** the production loop does NOT call `CassetteBridge.replay_corpus/0` synchronously per-slice (that would replay the whole corpus on every slice — slow, and couples prod→eval). Instead `corpus_pass_rate/1` reads a **pre-computed corpus health record** (the same file `mix conveyor.eval.replay` already writes for the scorecard: `eval/scorecards/inputs/cassette_flywheel.json`, the `replay_fidelity` metric value). If that file is absent (fresh checkout, corpus never replayed) ⇒ `nil` ⇒ `corpus_score → 0.5` (boost-neutral, never blocks).
- **Signature:**

```elixir
defmodule Conveyor.Replay.CorpusPassRate do
  @doc """
  Read the cassette-corpus replay fidelity (0.0..1.0) most recently written by
  `mix conveyor.eval.replay` (eval/scorecards/inputs/cassette_flywheel.json). Returns
  nil when no corpus health has been recorded (cold start) -> boost-neutral 0.5 in
  TrustScore. BOOST-only: never a hard gate (loop_integrity).
  """
  @spec read(opts :: keyword()) :: float() | nil
end
```

#### Wiring

- **File:** `lib/conveyor/planning/serial_driver.ex` — extend `inject_replay_divergence/4` (rename to `inject_replay_signals/4`) to ALSO put `output["corpus_pass_rate"]`:
  - `output |> Map.put("replay_divergence", status) |> maybe_put_corpus(opts)` where `maybe_put_corpus` puts the float only when non-nil (absent key ⇒ `corpus/1` in TrustEvidence defaults `nil`, identical to today).
- **No change to `trust_evidence.ex` `corpus/1`** (`:61-62`) — it already passes a float through and defaults non-float to `nil`. CONFIRMED correct as-is.

#### Discrimination test(s)

- **File:** `test/conveyor/replay/corpus_pass_rate_test.exs` (new, pure, non-`:eval`).
  1. `"reads a recorded corpus fidelity"` — write a temp `cassette_flywheel.json` with `replay_fidelity = 0.8`; `read(inputs_dir: tmp) == 0.8`. **GOOD path.**
  2. `"returns nil when no corpus health is recorded (cold start)"` — empty dir; `read == nil`. **Cold-start safety.**
- **File:** `test/conveyor/gate/trust_score_test.exs` (extend) — prove the BOOST is real (the raw rate is recorded) but STRICTLY NON-GATING (the clamp prevents corpus from alone parking a trustworthy run):
  - `"a low corpus pass rate is recorded but does NOT by itself abstain a trustworthy run (clamp at 0.5)"`: reference evidence (all non-corpus signals good) with `corpus_pass_rate: 0.0` ⇒ auto-accept score uses `max(0.5, 0.0) = 0.5` ⇒ `0.85 + 0.075 = 0.925 ≥ 0.9` ⇒ band `:auto_accept`. Assert `band == :auto_accept` AND that the *reported* raw corpus rate is `0.0` (the boost is visible/recorded even though it cannot park). **This proves corpus is reported-real but strictly boost-only** — it can never alone abstain a `trustworthy?`-passing run.
  - `"a cold-start nil corpus never blocks the otherwise-green reference"`: reference with `corpus_pass_rate: nil` ⇒ score `0.925 ≥ 0.9` ⇒ `:auto_accept`. **loop_integrity for cold start.**
  - **Anti-vacuity:** to prove the producer is real (not a no-op high number), assert the *reported* raw rate equals the cassette fidelity the producer read (a separate observability field), distinct from the clamped band-score contribution.

> **Calibration consequence (resolved by the clamp):** because the auto-accept band uses `max(0.5, corpus_rate)·0.15`, a low corpus fidelity can NEVER alone drop a `trustworthy?`-passing reference below 0.9 — the worst case is `0.85 + 0.075 = 0.925`. This eliminates the fail-OPEN→accidentally-fail-closed risk of wiring a volatile corpus number: a single failing cassette in a tiny corpus cannot spuriously park GOOD runs. The raw fidelity is still recorded and scorecard-tracked for observability. See re-calibration above.

#### Re-calibration (B2 wires a real, volatile number — re-tune to keep the reference safe)

- **The problem in numbers:** today `corpus_pass_rate` is `nil → 0.5` (boost-neutral). After B2, a real corpus fidelity of, say, `0.5` (1 of 2 cassettes failing) gives `corpus_score = 0.5` — SAME as nil, fine. But `0.0` gives `0.85` total ⇒ abstain. The **danger band is corpus < 0.333**, which a small corpus can hit on a single regression.
- **Decision (recommended, BAKED — corpus is made STRICTLY BOOST-only so it can NEVER alone park a `trustworthy?`-passing run):** keep weights at `replay 0.15 / corpus 0.15` but **clamp the corpus score contribution so it can never pull an otherwise-`trustworthy?`-passing run below the auto-accept threshold.** This mirrors how `corpus_pass_rate` is already excluded from the `trustworthy?/1` hard gate — we extend the same "never blocks" guarantee to the *score* path. Two layers, applied together:
  - **(A — the arithmetic clamp, the real fix) For a run that passes `trustworthy?/1`, floor the corpus component at 0.5** so corpus contributes `max(0.5, rate)·0.15` to the auto-accept score. With every other signal good (`0.85`), the worst-case corpus contribution is `0.5·0.15 = 0.075` → score floor `0.925 ≥ 0.9` → **a `trustworthy?`-passing run can NEVER abstain on corpus alone.** A genuinely-low corpus rate is still *reported* (the raw rate is recorded for the operator and the scorecard) and still lowers the *displayed* score component, but it cannot flip the band for an otherwise-perfect run. Concretely: `TrustScore.corpus_score/1` is used for the auto-accept band with `max(0.5, rate)`; the raw rate is surfaced separately for observability. This removes the need for the significance floor as a park-avoidance hack — corpus is now boost-only by construction, exactly like it is excluded from `trustworthy?`.
  - **(B — the significance floor, kept as an observability nicety, NOT a park-avoidance hack) `CorpusPassRate.read/1` still returns `nil` when `total < N` (`N = 5` cassettes)** so a 1-cassette corpus reads as boost-neutral rather than noisy 0.0/1.0 swings in the *reported* number. With clamp (A) in place this is no longer load-bearing for never-parking the reference — it is purely to keep the reported boost honest at small N.
  - **(Rejected) Lower the corpus weight to 0.10 and raise replay to 0.20** — perturbs the hard-signal weight and forces a full reference re-verify; more blast radius than the clamp. Rejected as overbuild.
- **The arithmetic, stated:** auto-accept score `= 0.30·integrity + 0.20·calibration + 0.20·baseline + 0.15·replay + 0.15·max(0.5, corpus_rate)`. For a `trustworthy?`-passing reference (all non-corpus signals = 1.0): `0.85 + 0.15·max(0.5, rate) ≥ 0.85 + 0.075 = 0.925 ≥ 0.9` for ANY `rate ∈ [0,1]`. Corpus can never alone abstain a trustworthy run. (A genuinely-bad corpus is still visible — reported raw, scorecard-tracked — and would lower the score for a run that is ALSO failing another signal, which is fine.)
- **Numbers before/after:** weights/threshold **UNCHANGED** (`replay 0.15, corpus 0.15, auto_accept 0.9`). The only changes are the `max(0.5, rate)` clamp on the corpus component in the auto-accept band and `CorpusPassRate.read/1`'s significance floor (observability only). The reference auto-accepts at every corpus size and every fidelity.
- **How verified the reference still accepts:** `trust_score_test.exs` `loop_integrity` test (unchanged, corpus 0.95 → accept) + the two new B2 score tests + `m1_codex_production_loop_test.exs` clean run (corpus file absent in that test's env → `nil` → accept).

#### Green criteria

- `mix test --exclude eval --seed 0` green incl. `corpus_pass_rate_test.exs` and the 2 new `trust_score_test.exs` assertions.
- format / warnings-as-errors / credo clean.
- `mix conveyor.eval.scorecard --gate` exits 0 (B2 reads the scorecard input but writes none).
- The `m1_codex_production_loop_test.exs` clean run stays `:passed` (corpus file absent → `nil` → reference accepts).

#### br issues closed

- Contributes to **`dr1m.1.4`** (corpus_pass_rate is the second consumed-but-unfed key the same issue family flagged). Primary closure is B1; B2 removes the second unfed key. (No separate br id located for corpus; if `A-recalibration` owns a `dr1m.1.x` corpus-weight issue, B2's significance-floor decision feeds it — flagged in `open_for_robert`.)

#### Risks / traps

- **(the headline trap) A real corpus number is VOLATILE and can accidentally convert a fail-OPEN boost into a fail-CLOSED park.** Mitigated by the significance floor (A). Without it, B2 would be a regression — a small corpus could park good runs. **This is the kind of "looks like progress, is actually a footgun" wiring the seed warns about; the significance floor is the brake.**
- **Prod→eval coupling.** Reading `eval/scorecards/inputs/cassette_flywheel.json` from the production loop is a soft coupling (prod reads an eval-written file). Acceptable (it's a read of a content-addressed metric, not a call into eval logic), but flag it: if `eval/` is absent in a deploy, `read → nil → boost-neutral` (safe). Documented in the module `@moduledoc`.
- **Staleness.** The corpus health file can be stale (last `mix conveyor.eval.replay`). Acceptable for a boost; do NOT let staleness affect a hard gate (it can't — corpus isn't in `trustworthy?/1`).

---

### B3 — Replace the report-level `replay_fidelity.status` hardcode with an honest value (human-summary honesty)

**Goal.** Remove the fabricated `"matched"` from the run *report* (`serial_driver.ex:147`) so the human summary (`conveyor.run.ex:72`) and the operator-tasks tests reflect reality, not a constant. This is the report-field half of dr1m.1.4 (B1 fixed the gate half).

- **File:** `lib/conveyor/planning/serial_driver.ex`, `replay_report/2` (`:135-152`).
- *Current (`:145-150`):* `replay_fidelity.status` is the literal `"matched"`.
- *Target:* derive the report-level status from the per-slice divergences accumulated across `events`. The driver now has each slice's `output["replay_divergence"]` (B1). **Decision:** the report `replay_fidelity.status` becomes:
  - `"matched"` only if EVERY event's `replay_divergence ∈ {:none, "none", nil}` (nil = a slice with no producer, e.g. skipped) — i.e. no slice diverged;
  - `"diverged"` if ANY event diverged;
  - `"unknown"` if any event is `:unknown` and none diverged.
  - **First-run honesty:** on a first run (baselines just recorded, all `:none`), `"matched"` is now TRUE-by-construction (every slice matched its just-recorded baseline / is a first observation) — so it's honest, not fabricated. The difference from today is it's *computed*, and a divergent rerun reports `"diverged"` instead of lying `"matched"`.
- **Consumer impact — the 2 tests that assert `"matched"`:**
  - `test/mix/tasks/conveyor_operator_tasks_test.exs:124,152` assert `replay_fidelity.status == "matched"`. These run CLEAN fixtures, so the computed status is still `"matched"` — they stay green WITHOUT edit. **Verify, don't assume:** run them; if a fixture has a non-`:none` slice, adjust the fixture, not the assertion.
  - `test/conveyor/first_light_serial_driver_test.exs:119,120` assert `result.report["replay_fidelity"]["status"] == "matched"` and the replay run too. Both are clean ⇒ still `"matched"`. Stay green.
- **New discrimination test** — `test/conveyor/planning/serial_driver_replay_report_test.exs` (or extend an existing driver test): a run where one injected store entry forces a slice `:diverged` ⇒ assert `report["replay_fidelity"]["status"] == "diverged"`. **This is the BROKEN-signal proof at the report level** — the old code could NEVER produce anything but `"matched"`.

- **Re-calibration:** none (report field, not a TrustScore input).
- **Green criteria:** `mix test --exclude eval --seed 0` green incl. the new diverged-report test; the 2 operator-tasks + first_light `"matched"` assertions stay green on clean fixtures; format/warnings/credo clean.
- **br issues closed:** completes **`dr1m.1.4`** (the report-field honesty half; B1 closed the gate half). Mark `dr1m.1.4` closed only after BOTH B1 and B3 land.
- **Risks/traps:** if a clean fixture has a skipped slice (`skipped_event/3`, `:123-133`, no `output`), its `replay_divergence` is absent (`nil`) — treat `nil` as `:none` for the report rollup (a skipped slice didn't diverge, it didn't run). Test a skip-and-continue fixture (m3) reports `"matched"` not `"unknown"`.

---

### B4 — Flag the genome historical-rate upgrade (tracking only — NO code this milestone)

**Goal.** Per SECONDARY DECISION, `corpus_pass_rate` initially sources from cassette-corpus fidelity (B2); the higher-fidelity source is the **Genome's historical labeled pass rate** for the slice/contract class. That is a larger, separate producer (requires the Genome to accrue labeled outcomes). B4 records the upgrade path as a tracked follow-on so it is not silently dropped.

- **No production code.** Create/annotate a br issue: `corpus_pass_rate: upgrade source from cassette-fidelity to Genome historical pass rate` (parent `dr1m.1`, label `reliability`, `calibration`). Body: B2 ships the cassette-fidelity boost (BOOST-only, significance-floored); the Genome historical rate is the eventual source once labeled outcomes accrue; the seam is `Conveyor.Replay.CorpusPassRate.read/1` (swap the source, keep the `float()|nil` contract and the significance floor). **The `read/1` contract is deliberately source-agnostic so this is a one-module swap, not a re-wire.**
- **Discrimination test:** n/a (tracking).
- **Re-calibration:** n/a now; when the Genome source lands, re-verify the reference auto-accepts against the new (likely higher-confidence, larger-N) historical rate, and revisit the significance floor (a Genome rate may be significant at smaller N).
- **Green criteria:** n/a (no code).
- **br issues closed:** opens 1 follow-on; closes none.
- **Risks/traps:** the trap is *forgetting* this and treating the cassette-fidelity boost as the final word. The cassette corpus measures *replay reproducibility*, NOT *outcome correctness* — they are different signals. Flag clearly in the `CorpusPassRate` `@moduledoc` that the current source is a reproducibility proxy, not a true historical correctness rate.

---

### Cross-slice summary for the executor

- **Land order:** B1 (with both unit + the `:eval` tampered-third-run falsifier) → B2 (with the significance floor) → B3 (report honesty) → B4 (br only). Green commit at each.
- **Weights/threshold:** **UNCHANGED across the entire sub-stream** (`integrity 0.30, calibration 0.20, baseline 0.20, replay 0.15, corpus 0.15, auto_accept 0.9`). The fail-closed flip is achieved by the *taxonomy* (first-run `:none`, divergence `:diverged`/`:unknown`→abstain) + the corpus *significance floor*, NOT by re-tuning. This is the cleanest possible re-calibration: zero weight churn, reference provably unmoved. If a later sub-stream's flip (hermeticity/provenance/canary) forces a weight change, MY numbers are stated explicitly so the global re-tune folds them in.
- **The one number a reviewer must re-derive themselves:** corpus danger band `< (0.9-0.85)/0.15 = 0.3333…`. Everything else follows from `:none → 1.0` already being the laundered default.
- **Anti-vacuity bottom line:** the sub-stream is real iff `slice_divergence_test.exs` test 3 (mutated baseline → `:diverged`), the `m1_codex` tampered-third-run (→ exactly that slice `parked`), and the B3 diverged-report test all FAIL when the producer is reverted to "always `:none`". Those three are the falsifiers; the green clean-run tests are necessary but NOT sufficient.

---

## Sub-stream E — Wire all 14 gate stages live + reachable failure branches + provenance/canary producers

> **Key:** `E-all-14-stages`
> **One-line:** Take the gate from 4 live stages to all 14, build the missing required producers (provenance + canary + the cheap static-stage context), make the dead `:policy_blocked` and critical stop-the-line Finalizer branches reachable, unify the three divergent hardcoded stage lists, and prove every newly-live stage discriminates a real defect — all under incremental fail-closed: a stage flips `required?: true` ONLY once its producer is real AND the known-good reference (`samples/beads_insight` + `samples/tasks_service`) still auto-accepts.

> **BRAKE-ON-COMPLEXITY (read first).** This is the largest sub-stream in M4 and the one most prone to *looks-wired-but-vacuous* failure. Ten dormant stages, three of which (`provenance_attestation`, `code_quality_delta`, `reviewer_aggregation`) are genuinely producer-less in a width-1 solo loop. The non-negotiable design rule below is: **a stage may only become `required?: true` when (a) a real producer fills its context keys for the known-good reference, AND (b) we have a discrimination test proving it FAILS on a real defect with the EXACT expected finding category, not merely `gate_passed == false`.** Every stage we cannot give a real producer in M4 stays `required?: false` (advisory) with a flagged Track-B follow-on — and we say so out loud. Do not "wire" a stage by feeding it a synthetic always-pass context; that is the exact vacuity trap that makes the gate a green rubber stamp. When in doubt, ship fewer stages live and correct, not all ten live and hollow.

---

### Verification of seed facts (done before designing — all confirmed against the real tree)

| Seed claim | Verified? | Note / correction |
| --- | --- | --- |
| `gate.ex` `run!/3` is list-driven; `stage_passes_gate?/1` at `:158-160` (`required?: false` OR `:passed` ⇒ pass); rescue at `:116-140` turns a stage exception into a FAILED required StageResult | ✅ | Exact. A stage reading a missing **required** input fails closed (parks); a stage reading a missing **optional** key and short-circuiting `:passed` is the silent false-positive. |
| Live today = 4 stages in `SerialDriver` | ✅ | File is `lib/conveyor/planning/serial_driver.ex` (seed said `serial_driver.ex` — full path differs). `@default_gate_stages` at **31-36** = `[ContractLock, DiffScope, SecretSafety, TestExecution]`. `default_gate_context/3` at **387-404** produces exactly: `agent_brief, artifacts, contract_lock, diff_policy, evidence, patch_set, security_findings, test_pack` (plus `run_attempt_id, run_attempt, run_spec, verification_result` merged in `run_gate!/4` at 367-373). |
| 14 stage modules in `lib/conveyor/gate/stages/`, canonical numbering in `droid-wiki/systems/gate.md` | ✅ | All 14 present. `gate.md:76-118` numbering confirmed (1 workspace_integrity … 14 canary_freshness). |
| DEAD Finalizer branches: `policy_violation` keys off `policy_file_change/policy_invocation_blocked/unredacted_secret/locked_path_touched/protected_path_change`; `critical_failure?` keys off `stale_canary/canary_false_negative` | ✅ | `finalizer.ex` `policy_blocking_category?/1` at **189-197**, `critical_failure?/1` at **181-187**. Today only `:needs_rework` (default) + secret_exposure (via SecretSafety's `unredacted_secret`) are reachable — confirm: `unredacted_secret` IS in the policy list and SecretSafety IS live, so `:policy_blocked` is *technically* reachable today via a secret, but `policy_file_change`/`locked_path_touched`/`protected_path_change`/`policy_invocation_blocked` and the entire critical/canary stop-the-line path are NOT (their producing stages are dormant). |
| DRIFT TRAP: `midflight_check.ex` has its OWN 4-stage list `[DiffScope, ContractLock, SecretSafety, AcceptanceMapping]` | ✅ | `lib/conveyor/gate/midflight_check.ex:31-36`. It is also a **hard allowlist** (`reject_non_allowlisted!/1` raises on anything outside it) — this matters: unifying must not silently widen the midflight oracle surface (see Slice E1). |
| EVAL harnesses each run only `[TestExecution]` | ✅ | `golden_thread.ex:33`, `lift_duel.ex:62`, `mutant_gauntlet.ex:29`, `attempt_loop.ex:238` (the latter as a `Keyword.get(opts, :gate_stages, [TestExecution])` default). |
| `GateResult` schema has `passed/stages/trust_score` but NO verdict/band column | ✅ | `lib/conveyor/factory/gate_result.ex:30-42`. Verdict/band lives on `RunAttempt.outcome` (`accepted/needs_rework/rejected/policy_blocked/abstained`) + `Slice.state`. |
| Build REAL producers for provenance + canary; reviewer ADVISORY | ✅ feasible | `provenance_attestation.ex` already reads everything from existing digests (base_commit, container_image_digest, test_pack_sha256, run_spec_sha256, policy_sha256, prompt_sha256, patch_sha256, artifacts) — a producer is an **assembler that surfaces digests the loop already has**, not new computation. `canary_freshness.ex` reads a `GateHealth` record; the producer is `RunGateCanary` (already exists, `lib/conveyor/jobs/run_gate_canary.ex`) emitting a `GateHealth` for the freshness key. `reviewer_aggregation` has no producer in a solo loop → advisory. |
| Canary corpus / `RunGateCanary` / `GateHealth` / freshness key already exist | ✅ (BONUS — not in seed) | `samples/tasks_service/.conveyor/canary/mutants.json` already contains **static-stage** mutants with patches present on disk: `test_weakened_or_deleted`→contract_lock, `forbidden_policy_edit`→policy_compliance, `repo_prompt_injection_ignored`→policy_compliance, `tool_output_injection_ignored`→run_check, `new_codescent_high_risk`→code_quality_delta. `samples/beads_insight/.conveyor/canary/mutants.json` is all behavioral (test_execution). This is the MutantGauntlet static-stage extension's raw material — sub-stream F's job to run them; ours to make the static stages real so F's run is honest. |
| `ToolchainRunner.docker_available?/0` exists | ✅ | `lib/conveyor/eval/toolchain_runner.ex:130` — **arity 0**, not `/1`. `hermeticity/1` at `:117` returns the honest 6-control map (`network: blocked` only under `:docker`). |
| TrustScore default weights/threshold | ✅ | `trust_score.ex:58-65`: weights `integrity 0.30, calibration 0.20, baseline 0.20, replay 0.15, corpus 0.15`; `auto_accept: 0.9`. `trustworthy?/1` (`:105-110`) is the hard gate: integrity trustworthy ∧ calibration valid ∧ baseline green ∧ replay none. **Critical:** wiring stages does NOT touch TrustScore — TrustScore adjudicates a *passed* gate; a stage failure makes `passed? == false` upstream and never reaches TrustScore. So this sub-stream does NOT re-calibrate trust weights (that is sub-stream D's surface). The re-calibration we own is the *gate-stage required/advisory matrix* + the canary false-pass threshold, not the trust band. (See "What this sub-stream does NOT touch" below.) |

**One correction to carry forward:** the seed said "today the only reachable live outcomes are `:needs_rework` (default) + secret_exposure." Precisely: `:policy_blocked` is *reachable today only via `unredacted_secret`* (SecretSafety is live and emits it). The other four policy categories and the entire critical/canary stop-the-line path are dead. Wiring `policy_compliance`/`observed_risk`/`workspace_integrity` makes `policy_file_change`/`locked_path_touched`/`protected_path_change`/`policy_invocation_blocked` reachable; wiring `canary_freshness` makes the critical stop-the-line path reachable.

---

### What this sub-stream does NOT touch (scope fence — brake on complexity)

- **TrustScore weights / `auto_accept` threshold / abstain band** — owned by sub-stream D (real trust producers + real abstain). We must NOT edit `trust_score.ex` or `trust_evidence.ex`. Our slices keep the known-good reference auto-accepting by keeping `passed? == true` on the reference; the trust band is downstream and unchanged. If any slice here makes the known-good reference's gate `passed? == false`, that is a bug in our producer, not a trust re-tune.
- **The hardened `DockerRunner` lifecycle** — decision 3: use the lighter `ToolchainRunner` docker path only. We never start `DockerRunner`.
- **`replay_divergence` / `corpus_pass_rate` producers** — owned by sub-stream D (secondary decisions). We only *consume* `GateHealth` for canary freshness.
- **The MutantGauntlet static-stage *execution loop*** — owned by sub-stream F. We provide the real static stages + the real static-stage *context producers* so F's run is non-vacuous; F drives the corpus through them and reports false-pass rate.
- **Data-integrity fixes dr1m.1.2 / dr1m.8** — owned by sub-stream B (data-integrity). Independent.

---

### Required/advisory matrix at M4 exit (the spine of the sequencing)

| # | Stage | M4 status | Producer source | br closed |
| --- | --- | --- | --- | --- |
| 1 | workspace_integrity | **required (live)** | `head_tree_sha256` + base_commit from RunSpec/RunAttempt/PatchSet (loop already has) | dr1m.E1 |
| 2 | diff_scope | required (already live) | unchanged | — |
| 3 | observed_risk | **required (live)** | `review_policy` (from project policy) + patch facts from PatchSet | dr1m.E3 |
| 4 | policy_compliance | **required (live)** | PatchSet changed_files + `tool_invocations` (from RunAttempt's tool ledger) | dr1m.E4 |
| 5 | secret_safety | required (already live) | unchanged | — |
| 6 | build_install | **advisory (non-blocking) at M4** | `build_install_result` only present on backends that build; ABSTAIN-not-fail when missing | dr1m.E6 (partial; required-flip flagged Track-B) |
| 7 | test_execution | required (already live) | unchanged | — |
| 8 | acceptance_mapping | **required (live)** | acceptance criteria from AgentBrief + `verification_result` (loop already has both) | dr1m.E8 |
| 9 | contract_lock | required (already live) | unchanged | — |
| 10 | code_quality_delta | **advisory (non-blocking) at M4** | only gate-blocking when a deterministic adapter contract exists; none does in M4 → advisory by its own design | dr1m.E10 (advisory; required-flip = real CodeScent adapter, Track-B) |
| 11 | run_check | **required (live)** | artifacts + artifact_contents + manifest (RunBundle) from the loop's projected artifacts | dr1m.E11 |
| 12 | provenance_attestation | **advisory-with-gated-required-flip at M4 exit** (real producer built + proven to DISCRIMINATE; flip to required gated on a pre-flip digest audit, else slips to early M5) | NEW `GateProvenanceContext` assembler from existing digests | dr1m.E12 (advisory at M4; required-flip gated) |
| 13 | reviewer_aggregation | **advisory (non-blocking)** | no producer in solo width-1 loop; real reviewer = Track-B/AI-reviewer follow-on | dr1m.E13 (advisory; real producer flagged) |
| 14 | canary_freshness | **advisory-with-gated-required-flip at M4 exit** (real `RunGateCanary`/`GateHealth` producer built + proven to DISCRIMINATE; flip to required gated on the canary-conductor pre-slice step + a fresh GateHealth row, else slips to early M5) | NEW: `RunGateCanary` emits a `GateHealth` health record keyed by freshness key (compose with sub-stream F) | dr1m.E14 (advisory at M4; required-flip gated) |

**Why these five (1,3,4,8,11) are the "anti-vacuity stages first":** they are the cheap, static, deterministic stages whose producers are *already in the gate context or trivially derivable* (no new measurement), and whose discrimination cases already exist as patches in `samples/tasks_service/.conveyor/canary/`. They give us the most fail-closed surface for the least producer risk. `provenance_attestation` (12) and `canary_freshness` (14) need a small new producer each; **for M4 these two are wired ADVISORY (built + proven to discriminate, but `required?: false`) with a GATED required-flip** (see the blast-radius brake below and Open Decision 16) — a brand-new 8-digest attestation and an every-slice canary-conductor dependency are too large a blast radius to make HARD auto-accept gates in the same milestone that first makes the gate honest. `build_install` (6), `code_quality_delta` (10), `reviewer_aggregation` (13) genuinely lack a width-1 producer → advisory with flagged follow-ons. **That is the honest M4 line: the cheap static stages (1,3,4,8,11 + already-live 2,5,7,9) required-live; provenance + canary advisory-but-discriminating with gated required-flips; build_install/code_quality_delta/reviewer advisory.** Every advisory stage still RUNS, records findings, and proves its BROKEN-half discrimination — the gate is strictly stronger at every step; only the *blocking* flip for provenance/canary is deferred behind a pre-flip verification.

> **BLAST-RADIUS BRAKE (provenance + canary required→advisory at M4 exit; softens Decision 4's "required" wording — elevated to Open Decision 16):** Decision 4 says "build REAL REQUIRED producers" for `provenance_attestation` and `canary_freshness`. We honor the *build + prove-real* half in full (the producers are real and the BROKEN-half discrimination tests land), but at M4 exit we wire them **advisory (`required?: false`)** rather than HARD auto-accept gates, because:
> - **Provenance** false-parks the reference on a SINGLE missing/nondeterministic digest out of ~8 (`base_commit`, `container_image_digest`, `test_pack_sha256`, `run_spec_sha256`, `policy_sha256`, `prompt_sha256`, `patch_sha256`, `evidence_sha256`). The loop is not yet verified to record all 8 for the reference (E6 itself discovers this mid-design). A required flip would park every run on the first absent digest.
> - **Canary** makes EVERY real slice park on `stale_canary` until `RunGateCanary` is wired into the conductor as a pre-slice step — a control-flow change to the production loop that is arguably M5/M6 conductor work, not M4 gate-honesty.
> **The gated required-flip (the condition to make them required, else SLIP to early M5):**
> - **provenance → required** is gated on a PRE-FLIP digest audit (E6 / the F7 verification): enumerate EVERY required digest and confirm the production loop records it for `beads_insight` + `gx` + `tasks_service`; only flip when the GOOD-half test against the real reference is green for all required digests.
> - **canary → required** is gated on the canary-conductor pre-slice step EXISTING (E7's `RunGateCanary`-into-`SerialDriver` wiring, see E7) AND a fresh green `GateHealth` row being written for the CURRENT freshness key before the flip.
> If either precondition is not met at M4 exit, that stage stays advisory and its required-flip is filed as an early-M5 follow-on. This removes the "one missing digest / unwired conductor parks every run" risk from the M4 exit bar while keeping the gate strictly stronger (findings visible, discrimination proven). **This is the DEFAULT; Robert can restore the stricter `required`-at-M4 posture if he accepts the producer/conductor build risk inside M4 — see Open Decision 16.**

> NOTE on br ids: the `dr1m.E*` ids above are *proposed* sub-issue ids under epic `dr1m` (Raw-Leverage Program). If the existing tracker prefers flat ids, create them as children of `dr1m` with the slugs given. The two pre-existing ids this sub-stream also advances: it makes the work in `bd50` ("Run real Codex through production … 6 stations + 4 gate stages + Finalizer") move from 4→14 gate stages, and it does NOT close `bd50` (live-Codex is the validation gate, owned by the exit criteria). It is independent of `dr1m.1.*` (trust) and `dr1m.8` (migration).

---

### Ordering within this sub-stream

```
E0  (unify lists + verdict column + advisory plumbing) ──┐
                                                          ├─> E1 workspace_integrity (required)
E0 ──────────────────────────────────────────────────────┼─> E2 acceptance_mapping (required)
                                                          ├─> E3 run_check (required)
                                                          ├─> E4 observed_risk (required)
                                                          └─> E5 policy_compliance (required)  ─> makes :policy_blocked reachable
E6 provenance_attestation (ADVISORY at M4 — real assembler built+proven; required-flip gated/deferred)  depends on E0
E7 canary_freshness (ADVISORY at M4 — GateHealth producer + conductor hook built+proven; required-flip gated/deferred)  depends on E0, coordinates with F
E8 build_install + code_quality_delta + reviewer_aggregation (ADVISORY wiring) depends on E0
E9 critical stop-the-line reachability proof depends on E7
E10 full-pipeline integration + scorecard --gate green over BOTH samples depends on E1..E9
```

E1–E5 are independent of each other after E0 and may be done in any order / parallel; E5 must precede E9-style policy-block proofs. E10 is the capstone.

---

### Cross-sub-stream dependencies

- **`depends_on`: `F-mutant-gauntlet`** — for E7 (canary freshness producer composes with the MutantGauntlet static-stage run that emits the `GateHealth` record) and for E10 (the full canary corpus false-pass gate is F's harness driving our 14 stages). Coordination contract: F calls `RunGateCanary.run!(stages: <the unified 14>, context: <real static context>)`; we own the stages + context producers, F owns the corpus loop + the scorecard `false_pass_rate` metric. **The `expected_catch.stage`/`category` in each mutant manifest is the shared contract** — our discrimination tests and F's harness must agree on it.
- **`depends_on`: `D-real-trust-abstain`** — soft. D owns abstain. Our reference must auto-accept (band `:auto_accept`), which requires D's trust producers to NOT abstain the known-good reference. We coordinate by keeping `passed? == true` on the reference; if D's slice lands first and tightens abstain, re-run our E10 green check. No code coupling.
- Independent of `B-data-integrity` (dr1m.1.2/.8).

---

### The non-negotiable per-stage proof obligation (anti-vacuity contract)

For EACH stage we flip to `required?: true`, the slice is not "done" until BOTH of these hold, each as a named test:

1. **GOOD-signal / known-good → ACCEPT.** With the *real producer* filling the context for the known-good reference, the stage returns `status: :passed`, the full gate `passed? == true`, and (in the integration test) the run finalizes `outcome: :accepted` / slice not parked. This catches the "contract_lock-style fail-close-on-missing-input" trap: if our synthetic/real context is wrong, the stage fails closed and the known-good reference would FALSE-PARK — the test must prove it does not.
2. **BROKEN-signal / real defect → the EXACT expected finding category.** With the matching mutant patch applied (real defect), the stage returns `status: :failed` AND `findings` contains the EXACT `expected_catch.category` for that stage (asserted by category string, e.g. `"locked_path_touched"`), AND the gate `passed? == false`. Asserting only `refute gate.passed?` is INSUFFICIENT and explicitly disallowed — a stage can reject the known-good by accident and "pass" a `refute passed?` test while being a false positive. The good-signal half (1) guards that; the category assertion guards "rejected for the right reason."

Both halves must be in the same test file per stage so a reviewer sees the symmetric proof.

---

### Slice E0 — Unify the three stage lists, add the `verdict` column, plumb advisory stages

**Goal:** One declared 14-stage pipeline (with per-stage `required?`), consumed by SerialDriver / MidflightCheck / the eval harnesses, so they can never diverge again; add a first-class `verdict` to `GateResult`; teach `Gate.run!` to carry advisory-stage findings without failing the gate. No stage flips live yet — this slice is pure plumbing and stays green by changing the *default lists to be equal to today's behavior* until E1+ flip stages on.

**New module:** `Conveyor.Gate.Pipeline` — `lib/conveyor/gate/pipeline.ex`.
Responsibility: the single source of truth for the ordered 14-stage pipeline and each stage's `required?` flag, plus named subsets.

```elixir
defmodule Conveyor.Gate.Pipeline do
  @moduledoc "Single declared gate pipeline. The ONLY place stage order + required? lives."
  alias Conveyor.Gate.StageSpec
  alias Conveyor.Gate.Stages

  # The full ordered pipeline. `required?` here is the M4 matrix; advisory stages
  # are required?: false so their findings are recorded but never fail the gate.
  @full [
    {Stages.WorkspaceIntegrity,     "workspace_integrity",     true},   # flips true in E1
    {Stages.DiffScope,              "diff_scope",              true},   # already live
    {Stages.ObservedRisk,           "observed_risk",           true},   # flips true in E4
    {Stages.PolicyCompliance,       "policy_compliance",       true},   # flips true in E5
    {Stages.SecretSafety,           "secret_safety",           true},   # already live
    {Stages.BuildInstall,           "build_install",           false},  # advisory (E8)
    {Stages.TestExecution,          "test_execution",          true},   # already live
    {Stages.AcceptanceMapping,      "acceptance_mapping",      true},   # flips true in E2
    {Stages.ContractLock,           "contract_lock",           true},   # already live
    {Stages.CodeQualityDelta,       "code_quality_delta",      false},  # advisory (E8)
    {Stages.RunCheck,               "run_check",               true},   # flips true in E3
    {Stages.ProvenanceAttestation,  "provenance_attestation",  false},  # advisory at M4 exit (E6 builds+proves real producer; required-flip GATED on digest audit, slips to M5 — Open Decision 16)
    {Stages.ReviewerAggregation,    "reviewer_aggregation",    false},  # advisory (E13)
    {Stages.CanaryFreshness,        "canary_freshness",        false}   # advisory at M4 exit (E7 builds+proves real producer; required-flip GATED on canary-conductor step, slips to M5 — Open Decision 16)
  ]

  # The cheap static, oracle-free subset for MidflightCheck (ADR-24). MUST stay a
  # strict subset that excludes test_execution + every execution/eval-oracle stage.
  @midflight_keys ~w(workspace_integrity diff_scope policy_compliance secret_safety acceptance_mapping contract_lock)

  @spec full() :: [StageSpec.t()]
  def full, do: Enum.map(@full, &to_spec/1)

  @spec live() :: [StageSpec.t()]   # the currently-flipped-required set; grows slice by slice
  def live, do: full()              # after E0 all 14 are in the list; required? flag controls blocking

  @spec midflight() :: [StageSpec.t()]
  def midflight, do: full() |> Enum.filter(&(&1.key in @midflight_keys))

  @spec required_keys() :: [String.t()]
  def required_keys, do: for({_m, k, true} <- @full, do: k)

  defp to_spec({module, key, required?}), do: %StageSpec{key: key, module: module, required?: required?}
end
```

**IMPORTANT sequencing subtlety (the green-at-every-commit constraint):** if E0 ships `@full` with all `required?: true` for stages whose producers are not yet real, the known-good reference will FALSE-PARK at the very first commit (because e.g. workspace_integrity reads a missing `head_tree_sha256` and fails closed). That violates incremental fail-closed. **Resolution:** E0 ships the pipeline with the *not-yet-producer-backed* stages as `required?: false` initially, and each later slice (E1…E5) flips ONE stage's flag from `false`→`true` in `@full` in the same commit that lands its producer + its discrimination test. So the `@full` table above is the *M4-exit* state; the *E0-commit* state has `workspace_integrity, observed_risk, policy_compliance, acceptance_mapping, run_check` at `required?: false` (each flips `true` in E1–E5), and only the 4 already-live (`diff_scope, secret_safety, test_execution, contract_lock`) at `true`. **`provenance_attestation` and `canary_freshness` stay `required?: false` THROUGH M4 exit** (advisory-with-gated-required-flip — E6/E7 build + prove their real producers but do NOT flip them required at M4; the required-flip is gated on a pre-flip verification and slips to early M5 — see the blast-radius brake above and Open Decision 16). `build_install`/`code_quality_delta`/`reviewer_aggregation` also stay `false` (E8 advisory). This keeps E0 byte-equivalent to today's behavior. (Write the table with the false flags in E0; each E1–E5 slice does a one-line `false → true` edit, the cleanest diff for Robert to audit; E6/E7 add the producer + discrimination tests WITHOUT the `false → true` flip.)

**Files changed in E0:**

| File:line | CURRENT | TARGET |
| --- | --- | --- |
| `lib/conveyor/planning/serial_driver.ex:31-36` | `@default_gate_stages = [ContractLock, DiffScope, SecretSafety, TestExecution]` | delete the module attr; `run_gate!/4` (line 379) calls `Keyword.get(opts, :gate_stages, Conveyor.Gate.Pipeline.full())`. At E0-commit, `Pipeline.full()` is behaviorally == old 4-live because the other 10 are `required?: false` (recorded, non-blocking). |
| `lib/conveyor/gate/midflight_check.ex:31-36` | own `@default_stages` list | `@default_stages` becomes `Conveyor.Gate.Pipeline.midflight()`. KEEP the `reject_non_allowlisted!/1` guard but rebase the allowlist on `Pipeline.midflight()` so the hidden-oracle guarantee is preserved AND single-sourced. **Trap:** `Pipeline.midflight()` now includes `policy_compliance` + `workspace_integrity` which were NOT in the old midflight set — confirm both are still cheap/static/oracle-free (they are: no test execution, no eval oracle). Add `run_check` only if cheap (it reads artifact bytes — keep it OUT of midflight to avoid surfacing the prompt-injection oracle mid-flight; it stays gate-only). The midflight set is `workspace_integrity, diff_scope, policy_compliance, secret_safety, acceptance_mapping, contract_lock` — 6 cheap static stages, deliberately excluding `run_check`/`observed_risk`(DB writes)/`provenance`/`canary`. |
| `lib/conveyor/eval/golden_thread.ex:33`, `lift_duel.ex:62`, `mutant_gauntlet.ex:29` | each `@stages/@gate_stages = [TestExecution]` | leave the EVAL harness defaults at `[TestExecution]` for now (they are single-stage discrimination harnesses by design — golden_thread/lift_duel measure behavioral lift; widening them is sub-stream F's MutantGauntlet job). Add a module doc note: "single-stage by design; the full pipeline is `Conveyor.Gate.Pipeline.full/0`." **Do NOT unify the eval harnesses' stage list into the pipeline** — that would change what those evals measure and is out of scope. The "three hardcoded lists" the seed flags are SerialDriver + MidflightCheck + AttemptLoop's gate default; unify THOSE three. |
| `lib/conveyor/attempt_loop.ex:238` | `Keyword.get(opts, :gate_stages, [TestExecution])` | `Keyword.get(opts, :gate_stages, Conveyor.Gate.Pipeline.full())`. **Trap:** AttemptLoop's rework path is injected by SerialDriver with the driver's own `run_gate` closure (serial_driver.ex:230), so AttemptLoop's default only bites when AttemptLoop is used standalone — but unify it anyway so a standalone rework run gets the full pipeline. Verify the existing `attempt_loop_test.exs` still passes (it injects fixtures, so the default change should be inert; if a test relies on `[TestExecution]` exactly, pass `gate_stages: [TestExecution]` explicitly in that test). |

**`GateResult.verdict` column:**

| File | Change |
| --- | --- |
| `lib/conveyor/factory/gate_result.ex:42` (after `trust_score`) | add `attribute :verdict, :atom do constraints one_of: [:accepted, :needs_rework, :policy_blocked, :rejected, :abstained]; public? true end` (nullable; nil for legacy rows). |
| NEW migration | `priv/repo/migrations/*_add_gate_result_verdict.exs` — add nullable `verdict` text column. Reversible (drop column). Run `mix ash_postgres.generate_migrations --name add_gate_result_verdict`. |
| `lib/conveyor/gate/finalizer.ex:97-106` `persist_gate_result!/2` | compute `verdict` from the same classification the Finalizer already derives and write it onto the GateResult. Wire it: in `finalize!/3` the `{transition, _}` tuple already knows the outcome; thread `verdict` into `persist_gate_result!`. The verdict is: `:accepted` (pass+auto_accept), `:abstained` (pass+abstain), or the `classify_failure/1.outcome` (`:needs_rework`/`:policy_blocked`/`:rejected`). This makes the accept/park/abstain/reject distinction first-class + queryable on `GateResult`, not only inferred from `RunAttempt.outcome`. |

**Why the verdict column (decision rationale, bake it):** the seed flags that the distinction lives only on `RunAttempt.outcome` + `Slice.state`. A `GateResult` row today cannot tell you *why* a gate parked without joining two other tables. Adding `verdict` makes the canary corpus + scorecard auditable directly off `GateResult` and lets E10's `--gate` check assert verdicts without re-deriving them. Low complexity (one nullable column + one assignment), high audit leverage. **RECOMMENDED, baked.**

**Discrimination test for E0:** `test/conveyor/gate/pipeline_test.exs`
- `test "pipeline is the single source for SerialDriver, MidflightCheck, AttemptLoop"` — asserts `Pipeline.full()` has 14 specs in `gate.md` order; asserts `MidflightCheck.default_stages()` == `Pipeline.midflight()`; asserts `MidflightCheck` still raises on `[Stages.TestExecution]` (hidden-oracle guard intact).
- `test "at E0 the pipeline is behaviorally equivalent to the legacy 4-live set"` — runs `Gate.run!(known_good_context, Pipeline.full())` against the beads_insight known-good fixture and asserts `passed? == true` (the 10 not-yet-flipped stages are `required?: false`, so their findings are recorded but non-blocking → no false-park). **This is the anti-vacuity guard for the unification itself: it proves we did not accidentally fail-close the reference.**
- `verdict` test in `test/conveyor/gate/finalizer_test.exs`: a passing finalize writes `gate_result.verdict == :accepted`; a needs-rework finalize writes `:needs_rework`.

**Green criteria:** `mix test --exclude eval --seed 0` green (existing serial_driver / midflight / attempt_loop / finalizer tests pass unchanged + new pipeline test). `mix conveyor.eval.scorecard --gate` unchanged (no new blocking metric yet). No `mix format` / credo / warnings-as-errors regressions.

**br closed:** none yet (E0 is enabling). **Risks/traps:**
- *Midflight allowlist widening:* unifying must not let a hidden oracle into midflight. Mitigated by keeping `run_check`/`test_execution` out of `@midflight_keys` and the explicit raise-test.
- *Ash one_of on verdict:* `:abstained`/`:policy_blocked` must be in the constraint list or the create raises. Test both.
- *AttemptLoop default change cascading into a test that asserts exact stage count* — pin that test with an explicit `gate_stages:` opt.

---

### Slice E1 — `workspace_integrity` → required (live)

**Goal:** The gate fails closed when the patch's base commit drifts, the patch does not apply cleanly, locked paths are touched, or the workspace head-tree digest was never recorded — and the known-good reference still passes.

**Stage read (`workspace_integrity.ex:11-58`) — context keys consumed:** `:patch_set` (with `:base_commit`, `:applies_cleanly`, `:touches_locked_paths`, `:patch_ref`), `:run_spec` (`:base_commit`), `:run_attempt` (`:base_commit`, `:head_tree_sha256`), `:head_tree_sha256`. Fails closed if `patch_set` is nil (`missing_patch_set`) or `head_tree_sha256` is nil (`missing_head_tree_sha256`).

**Producer:** SerialDriver `default_gate_context/3` (serial_driver.ex:387-404) already surfaces `:patch_set`, and `run_gate!/4` already merges `:run_spec`, `:run_attempt`. The ONLY missing key is `:head_tree_sha256`. **Where it comes from:** the workspace HEAD tree object. Add to `default_gate_context/3`:
```elixir
head_tree_sha256: head_tree_sha256(run_attempt, run_spec)
```
where `head_tree_sha256/2` resolves it from (a) `run_attempt.head_tree_sha256` if recorded, else (b) `git -C <workspace> rev-parse HEAD^{tree}` via the existing `workspace_path/1` helper (serial_driver.ex:565), else (c) nil. The `patch_set` must carry `:applies_cleanly` and `:touches_locked_paths` — confirm the PatchSet resource has these (it is read via `patch_set_for/1`). If `:applies_cleanly` is not populated by the implementer station, default it to `true` ONLY when the patch is known to have been applied (the slice ran), and add a `:touches_locked_paths` boolean computed from `changed_files` ∩ contract_lock protected globs.

> **Honest-taxonomy decision (bake):** `head_tree_sha256` is *always assessable* on every backend (it is a git object), so its absence is "should be measured but missing" → fail-closed (`missing_head_tree_sha256` blocking). It is NOT a `not_assessed` case. Contrast with hermeticity in E7/E8.

**CURRENT → TARGET:**
- `serial_driver.ex:387-404` `default_gate_context/3`: add `head_tree_sha256` key + `applies_cleanly`/`touches_locked_paths` enrichment on the patch_set map.
- `lib/conveyor/gate/pipeline.ex` `@full`: flip `workspace_integrity` `false → true`.

**Discrimination tests:** `test/conveyor/gate/stages/workspace_integrity_discrimination_test.exs`
- `test "known-good reference: workspace_integrity passes and the gate accepts"` — beads_insight reference context (real `head_tree_sha256`, base matches) → stage `:passed`, `Gate.run!` `passed? == true`. **(GOOD half — guards false-park.)**
- `test "base-commit drift parks with base_commit_mismatch"` — set `run_spec.base_commit != patch_set.base_commit` → assert stage `:failed` AND `"base_commit_mismatch"` in finding categories AND `gate.passed? == false`. **(BROKEN half, exact category.)**
- `test "missing head tree digest parks with missing_head_tree_sha256"` — drop `:head_tree_sha256` → exact category `"missing_head_tree_sha256"`, gate `passed? == false`.
- `test "locked-path touch parks with locked_path_touched"` — `touches_locked_paths: true` → exact category `"locked_path_touched"`; ALSO assert (in `finalizer_test`) that this category routes to `:policy_blocked` outcome (it is in `policy_blocking_category?/1`). This is the first slice that makes a non-secret `:policy_blocked` path reachable.

**Re-calibration:** none (no trust weight/threshold change; the gate-pass set tightens by one stage). Verify the known-good reference still `:auto_accept` by re-running the E0 equivalence test with workspace_integrity now `required?: true` — it must stay `passed? == true`. Record before/after in the PR body: before = workspace_integrity advisory; after = required, beads_insight + tasks_service known-good still pass.

**Green criteria:** `mix test --exclude eval --seed 0` green (new discrimination test + unchanged). The MutantGauntlet/canary corpus (sub-stream F) over tasks_service must still show `false_positive_count == 0` for the known-good with workspace_integrity live. `mix conveyor.eval.scorecard --gate` green.

**br closed:** `dr1m.E1`. **Risks/traps:** *the head-tree git call can fail in map-fake unit tests (no real workspace)* — guard with the `workspace_path/1 == nil → nil` path AND make the unit discrimination tests pass `head_tree_sha256` explicitly so they do not shell out. *`applies_cleanly` default* — if defaulted to `true` blindly it is vacuous; only default true when the slice actually ran and the patch applied (otherwise the producer is a rubber stamp). Flag: a more rigorous `applies_cleanly` (re-apply the patch to a fresh checkout) is a Track-B hardening; M4 trusts the slice's own apply result.

---

### Slice E2 — `acceptance_mapping` → required (live)

**Goal:** The gate fails closed when an acceptance criterion has missing/skipped/failed evidence; passes when every criterion maps to passing evidence.

**Stage read (`acceptance_mapping.ex:11-49`):** `:acceptance_mapping` (pre-computed result) OR `:acceptance_results` OR (`:acceptance_criteria` ‖ `agent_brief.acceptance_criteria`) + `:verification_result` → it calls `AcceptanceMapper.map!/2`. `:allowed_skipped_acceptance_refs`. Fails closed (`missing_acceptance_mapping`) when none present or zero criteria.

**Producer:** the loop already has both `agent_brief` (with `acceptance_criteria`, surfaced in `default_gate_context` via `contract.agent_brief`) and `verification_result` (merged in `run_gate!/4` from `slice_result.output["verification_result"]`). So the stage will compute via `AcceptanceMapper.map!(criteria, verification_result)`. **No new context key needed** — but verify `agent_brief.acceptance_criteria` is non-empty for the reference (beads_insight has AC-001..AC-016). If it is empty the stage fails closed with `missing_acceptance_mapping` — which would FALSE-PARK the reference. **The producer's real job here is to guarantee acceptance_criteria reaches the context.** Add a guard in `default_gate_context/3`: surface `acceptance_criteria: contract.agent_brief && contract.agent_brief.acceptance_criteria` explicitly so the stage does not have to dig through `:agent_brief`.

> **Vacuity trap (dr1m.7 cousin):** `AcceptanceMapper` over an empty criteria set or a `verification_result` with `"suites" => []` can map to zero results and "pass." The stage already fails closed on `acceptance_results == []` (line 71-78) — GOOD. But confirm the reference's `verification_result` actually carries acceptance suites; if it carries only `baseline_regression`, the mapper finds no acceptance evidence and the stage parks the reference. The GOOD-half test below is what catches this.

**CURRENT → TARGET:**
- `serial_driver.ex:387-404`: add `acceptance_criteria` explicit key.
- `pipeline.ex` `@full`: `acceptance_mapping` `false → true`.

**Discrimination tests:** `test/conveyor/gate/stages/acceptance_mapping_discrimination_test.exs`
- GOOD: beads_insight reference context (16 criteria, all `evidence_status: passed`) → stage `:passed`, gate `passed?`.
- BROKEN: one criterion `evidence_status: "failed"` → exact category `"failed_acceptance_evidence"`, gate `passed? == false`.
- BROKEN: one criterion `evidence_status: "missing"` → exact category `"missing_acceptance_evidence"`.
- BROKEN: empty criteria → exact `"missing_acceptance_mapping"` (proves the dr1m.7 vacuity is fail-closed, not silently-pass).

**Re-calibration:** none. Re-run reference equivalence with acceptance_mapping required → still `passed?`. **Green:** as E1. **br closed:** `dr1m.E8`. **Risks:** *the reference's verification_result must include acceptance suite results* — if the production loop's verification only reruns baseline, acceptance_mapping false-parks the reference. Mitigation: the GOOD-half test runs against the *real* beads_insight reference verification_result; if it parks, that is a real producer gap to fix in the loop (surface acceptance suite results), NOT a reason to make the stage advisory.

---

### Slice E3 — `run_check` → required (live)

**Goal:** Fail closed on artifact schema/digest/manifest mismatches and on prompt-injection markers in artifact output; pass on a consistent run bundle.

**Stage read (`run_check.ex:33-59`):** `:artifacts`, `:artifact_contents` (list of `{projection_path, content}`), `:manifest` ‖ decoded `manifest.json`, `:run_bundle` (`:schema_version`, `:manifest_sha256`, `:bundle_root_sha256`, `:manifest_ref`), `:required_artifact_paths`. Checks: required artifacts present, supported schema_version, content hash == metadata, manifest digests, prompt-injection markers (`@injection_markers`).

**Producer:** `:artifacts` already surfaced (`artifacts_for/1`). MISSING: `:artifact_contents` and `:run_bundle`/`:manifest`. **New producer:** add `:artifact_contents` by reading each artifact's blob bytes from the BlobStore (the loop has `:blob_root` in opts) and `:manifest` from the RunBundle the slice produced. Add to `default_gate_context/3` (or a small `GateArtifactContext` helper to keep `default_gate_context` lean):
```elixir
artifact_contents: artifact_contents(artifacts, blob_root),   # [{projection_path, bytes}]
manifest: run_bundle_manifest(run_attempt, blob_root),
run_bundle: run_bundle_for(run_attempt)
```
**Honest taxonomy:** if the slice produced no RunBundle/manifest (some backends), the stage fails closed with `missing_manifest` — this IS "should be measured but missing," NOT not-assessable. The loop SHOULD always emit a manifest (it is the dossier+verification.json bundle), so missing-manifest is a real defect. The reference must carry `dossier.md` + `logs/verification.json` (the `@required_artifact_paths`).

**CURRENT → TARGET:** add the three keys; `pipeline.ex` flip `run_check` `false → true`.

**Discrimination tests:** `test/conveyor/gate/stages/run_check_discrimination_test.exs`
- GOOD: reference run bundle (dossier + verification.json + consistent manifest) → `:passed`, gate `passed?`.
- BROKEN: tampered artifact content (hash != metadata) → exact `"artifact_hash_mismatch"`, gate `passed? == false`.
- BROKEN: missing `dossier.md` → exact `"missing_required_artifact"`.
- BROKEN: `tool_output_injection_ignored` mutant (artifact content contains "ignore the locked contract") → exact `"untrusted_instruction_followed"`, gate `passed? == false`. **This matches the `tool_output_injection_ignored` mutant in `samples/tasks_service/.conveyor/canary/mutants.json` whose `expected_catch.stage == "run_check"`.** (Note: the manifest's `expected_catch.category` is `"prompt_injection_marker"` but the stage emits `"untrusted_instruction_followed"`; **reconcile the manifest category to the real stage category** — this is a manifest-vs-code drift the seed warned about. Update the manifest `expected_catch.category` to `"untrusted_instruction_followed"` and keep `prompt_injection_marker` in `valid_stricter_categories`, OR add `prompt_injection_marker` as an alias finding. RECOMMENDED: fix the manifest to the real category; document the change in the PR.)

**Re-calibration:** none. **Green:** as E1; the F canary corpus now exercises run_check live for `tool_output_injection_ignored` and must catch it (`false_negative_count` unchanged at 0). **br closed:** `dr1m.E11`. **Risks:** *reading artifact bytes requires `blob_root`* — in map-fake unit tests inject `:artifact_contents` directly. *Manifest digest computation is expensive over large bundles* — acceptable, gate is end-of-slice. *The injection-marker list is a denylist* — known incompleteness; flag as Track-B (semantic injection detection), but the canary mutant proves the denylist catches the planted marker.

---

### Slice E4 — `observed_risk` → required (live)

**Goal:** Fail closed when observed patch risk exceeds planned risk under a fail-closed escalation policy, or when a rule requires human approval that was not granted; pass on a low-risk in-scope patch.

**Stage read (`observed_risk.ex:16-51`):** `:patch_set` (changed_files, lines_added/deleted, touches_locked_paths), `:review_policy` (with `:risk_rules`, `:default_required_review_kinds`, `:escalation_policy`), `:planned_risk`, `:human_approval_granted`. **It PERSISTS a `RiskAssessment`** (`maybe_persist_assessment/3`) when `run_attempt_id` + `patch_set_id` present. Fails closed if `patch_set` or `review_policy` is nil.

**Producer:** `:patch_set` already surfaced. MISSING: `:review_policy` and `:planned_risk`. **Where from:** the project/slice policy. Add `:review_policy` from the slice's `DiffPolicy`/project policy (the loop has the slice; the review policy is the project's risk configuration) and `:planned_risk` from the slice metadata (default `"low"`). Add to `default_gate_context/3`:
```elixir
review_policy: review_policy_for(run_attempt.slice_id),
planned_risk: planned_risk_for(run_attempt.slice_id)
```
**CRITICAL fail-closed-on-missing-input trap:** `observed_risk` fails closed if `review_policy` is nil → the reference would FALSE-PARK if the project has no review policy configured. **Decision (bake):** ship a *default project review policy* (a real `ReviewPolicy` record or a config-default map) with `escalation_policy: :allow_with_warning` and an empty/low-risk `risk_rules` set for the sample projects, so the reference's low-risk patches pass (observed == planned == low → no finding). The default policy must be a real, committed artifact (e.g. `samples/<project>/.conveyor/policies/review_policy.yml`), NOT a synthetic always-empty map injected at the gate — that distinction is the difference between a real producer and vacuity.

**CURRENT → TARGET:** add `review_policy` + `planned_risk` keys + the committed default review policy for both samples; `pipeline.ex` flip `observed_risk` `false → true`.

**Discrimination tests:** `test/conveyor/gate/stages/observed_risk_discrimination_test.exs`
- GOOD: reference low-risk patch + default review policy → stage `:passed` (observed == planned), gate `passed?`. ALSO assert a `RiskAssessment` row is persisted (the stage's side effect is real, not skipped).
- BROKEN: patch touches `mix.exs` (dependency change) under a rule `{when: %{dependency_changes: true}, observed_risk: "high"}` with planned `"low"` and `escalation_policy: :fail_closed` → exact category `"observed_risk_exceeds_planned"` with `severity: "blocking"`, gate `passed? == false`.
- BROKEN: rule with `require_human_approval: true`, no approval → exact `"human_approval_required"`, gate `passed? == false`.
- GOOD-negative: same risk exceedance under `escalation_policy: :allow_with_warning` → finding present but `severity: "warning"` → stage `:passed`, gate `passed?` (proves the escalation policy is honored, not just "any finding fails").

**Re-calibration:** none (gate-stage). Re-run reference equivalence. **Green:** as E1. **br closed:** `dr1m.E4`. **Risks:** *RiskAssessment persistence requires DB* — unit discrimination tests inject `run_attempt_id`/`patch_set_id` or run under DataCase; map-fake tests omit ids (the stage's `maybe_persist` no-ops). *Default review policy too permissive = vacuous* — the policy must encode at least the dependency/migration/locked-path rules so the BROKEN cases fire; an empty rule set would never block, making the stage a rubber stamp. The BROKEN-half tests guard this.

---

### Slice E5 — `policy_compliance` → required (live); `:policy_blocked` Finalizer branch reachable

**Goal:** Fail closed (→ `:policy_blocked`) when a patch edits a protected policy file or a tool invocation was blocked/denied; pass when neither.

**Stage read (`policy_compliance.ex:20-38`):** `:patch_set` (changed_files), `:policy_path_globs` (defaults to `@default_policy_path_globs`), `:tool_invocations` (each with `:policy_decision`/`:status`). Fails closed if `patch_set` nil.

**Producer:** `:patch_set` already surfaced. MISSING: `:tool_invocations`. **Where from:** the RunAttempt's tool-invocation ledger (the loop records tool calls; surface them). Add `:tool_invocations: tool_invocations_for(run_attempt.id)` to `default_gate_context/3`. `:policy_path_globs` uses the stage default (correct — policy files are repo-relative globs). For the sample projects, ensure NO reference file matches the policy globs (the reference does not edit policies → no `policy_file_change` finding → passes).

**CURRENT → TARGET:** add `tool_invocations`; `pipeline.ex` flip `policy_compliance` `false → true`.

**Discrimination tests:** `test/conveyor/gate/stages/policy_compliance_discrimination_test.exs`
- GOOD: reference patch (no policy files, no blocked invocations) → `:passed`, gate `passed?`.
- BROKEN: `forbidden_policy_edit` mutant (changes a protected policy file) → exact `"policy_file_change"`, gate `passed? == false`. Matches the `forbidden_policy_edit` mutant in `samples/tasks_service/.conveyor/canary/mutants.json` (`expected_catch.stage == "policy_compliance"`, `category == "policy_file_change"`).
- BROKEN: a `tool_invocation` with `policy_decision: :blocked` → exact `"policy_invocation_blocked"`, gate `passed? == false`.
- **Finalizer-reachability test** (`test/conveyor/gate/finalizer_test.exs`): a gate result whose findings contain `"policy_file_change"` → `classify_failure/1` returns `outcome: :policy_blocked`, `slice_action: :policy_block`; assert the RunAttempt transitions to `outcome: :policy_blocked` and `GateResult.verdict == :policy_blocked` and the Slice state is `:policy_blocked`. **This proves the dead `:policy_blocked` branch (finalizer.ex:161-168) is now reachable end-to-end, not just in code.**

**Re-calibration:** none. **Green:** as E1; canary corpus catches `forbidden_policy_edit` + `repo_prompt_injection_ignored` live. **NOTE on `repo_prompt_injection_ignored` (reconciled with F4 — single disposition):** its original `expected_catch.stage == "policy_compliance"`, `category == "repo_prompt_injection"` is wrong — `policy_compliance` does NOT emit `repo_prompt_injection`. **F4 VERIFIED** the README marker "ignore the locked contract" IS in `run_check`'s `@injection_markers` and fires `untrusted_instruction_followed` when the README is fed as artifact content. **DEFAULT (recommended, consistent with F4): RE-POINT** `repo_prompt_injection_ignored.expected_catch.stage → run_check`, `category → untrusted_instruction_followed` (F4 owns this manifest edit and feeds the README as artifact content). The alternative (disable with a Track-B "repo-source injection scanning" follow-on) is the fallback IF the prose does not land in a gate-visible artifact. Do NOT leave it asserting a category no stage emits. *See Open Decision 12 — reroute-vs-disable; reroute is the default since F4 proved it catchable.* **br closed:** `dr1m.E5`. **Risks:** *tool_invocations ledger may be empty in the reference* (no blocked calls) → fine, passes. *The policy globs default includes `lib/conveyor/policy/**`* — for SAMPLE projects this is irrelevant (their files are under `src/`/`tasks_service/`); ensure the sample's policy file path (`samples/<x>/.conveyor/policies/**`) is in the globs so `forbidden_policy_edit` is caught.

---

### Slice E6 — `provenance_attestation` → ADVISORY at M4 (real producer built + proven; required-flip gated/deferred — Open Decision 16); NEW `GateProvenanceContext` assembler

**Goal:** The gate mints + validates a real in-toto/SLSA provenance statement from digests the loop already has, fails closed on a missing required subject/material/invocation digest, and passes for the reference.

**Stage read (`provenance_attestation.ex:28-42`):** builds a statement from `:provenance_subjects`, `:artifacts`, `:patch_sha256`/`patch_set.patch_sha256`, `:evidence_sha256`/`evidence.sha256`, `:provenance_materials`, `:base_commit`/run_spec, `:container_image_digest`, `:test_pack_sha256`, `:run_spec_sha256`, `:policy_sha256`, `:prompt_sha256`, `:command_invocations`, `:run_bundle_root_sha256`. **It PERSISTS an Artifact** (`maybe_persist`) when `run_attempt_id` + `blob_root` present and findings empty. Required: subjects `diff.patch`+`evidence.json` with sha256; materials `source`(gitCommit)+`container-image`(sha256)+`test-pack`(sha256); invocation digests `run_spec_sha256`+`policy_sha256`+`prompt_sha256`.

**New module:** `Conveyor.Gate.GateProvenanceContext` — `lib/conveyor/gate/gate_provenance_context.ex`.
Responsibility: assemble the provenance context keys from the loop's existing records (no new measurement; pure surfacing of digests already computed). Called from `serial_driver.ex` `default_gate_context/3` (merged into the gate context).

```elixir
defmodule Conveyor.Gate.GateProvenanceContext do
  @moduledoc "Surfaces the digests the loop already has into provenance-attestation context keys."
  @spec from(run_spec :: map(), run_attempt :: map(), slice_result :: map(), keyword()) :: map()
  def from(run_spec, run_attempt, slice_result, opts) do
    %{
      base_commit: run_spec.base_commit,                       # source material (gitCommit)
      container_image_digest: run_spec.container_image_digest, # container-image material
      test_pack_sha256: run_spec.test_pack_sha256,             # test-pack material
      run_spec_sha256: run_spec_sha256(run_spec),              # invocation digest
      policy_sha256: run_spec.policy_sha256,                   # invocation digest
      prompt_sha256: prompt_sha256(run_attempt, slice_result), # invocation digest
      patch_sha256: patch_sha256(slice_result),                # diff.patch subject
      evidence_sha256: evidence_sha256(slice_result),          # evidence.json subject
      blob_root: Keyword.get(opts, :blob_root)                 # to persist the in-toto artifact
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
  end
end
```

**CRITICAL fail-close-on-missing-input trap (the seed's headline trap) — WHY provenance is ADVISORY at M4 exit:** every one of these digests is REQUIRED for a `required?: true` stage; if any is nil the stage fails closed and the reference FALSE-PARKS. The GOOD-half test must prove the reference has ALL of: base_commit, container_image_digest, test_pack_sha256, run_spec_sha256, policy_sha256, prompt_sha256, patch_sha256, evidence_sha256. **The loop is NOT yet verified to record all 8 for the reference** (this slice discovers it mid-design). So at M4 exit provenance is wired **advisory (`required?: false`)** — built, discriminating, findings visible — and the **required-flip is GATED on a pre-flip digest audit** (below). **Backend taxonomy for container-image** (applies whenever provenance IS evaluated, advisory or required): `container-image` material is "not assessable on a backend with no container" → `not_assessed`/NON-blocking under `:local`, required under `:docker`. Implement as a backend-aware *required-materials* set: the stage's `@required_materials` includes `container-image` only when `context[:hermetic_backend] == :docker`. Make `material_findings/1` skip the `container-image` requirement when `value(context, :container_backend) != :docker`, emitting an informational (non-blocking) `provenance_container_not_assessed` finding instead.

**PRE-FLIP DIGEST AUDIT (the gate on a future provenance→required flip — F7):** before provenance can ever be flipped `required?: true` (an early-M5 follow-on, NOT M4), add an explicit verification step that ENUMERATES each required digest (`run_spec_sha256`, `policy_sha256`, `prompt_sha256`, `evidence_sha256`, `patch_sha256`, `test_pack_sha256`, `base_commit`, and `container_image_digest` under `:docker`) and confirms the production loop records it for `beads_insight` + `gx` + `tasks_service`. Grep the producers that write `run_spec_sha256`/`policy_sha256`/`prompt_sha256`/`evidence_sha256`; if any is absent, that is a producer slice that must land FIRST (named, with file). Do NOT flip provenance required until the GOOD-half test against the real reference is green for ALL required digests. If the audit is not complete at M4 exit, provenance stays advisory and the required-flip is filed as an early-M5 follow-on (see the br-creation action in H7).

**CURRENT → TARGET:**
- NEW `lib/conveyor/gate/gate_provenance_context.ex`.
- `serial_driver.ex:387-404`: `Map.merge(GateProvenanceContext.from(run_spec, run_attempt, slice_result, opts))`.
- `provenance_attestation.ex:226-243` `material_findings/1`: make `container-image` conditional on `:docker` backend (see above) — small, surgical.
- `pipeline.ex`: provenance_attestation stays `required?: false` at M4 (advisory). **No `false → true` flip in E6.** The producer + discrimination tests land; the flip is gated/deferred per the digest audit above.

**Discrimination tests:** `test/conveyor/gate/stages/provenance_attestation_discrimination_test.exs`
- GOOD (docker context): full digests present → stage `:passed`, gate `passed?`, AND (under DataCase + blob_root) a `provenance.intoto.json` Artifact is persisted (`kind: "provenance"`, `schema_version: "conveyor.provenance@1"`). Assert the persisted statement validates (subjects have sha256, materials have digests).
- GOOD (local context): same but `container_backend: :local`, no `container_image_digest` → stage `:passed` with a non-blocking `provenance_container_not_assessed` finding, gate `passed?`. **(Proves the not-assessable taxonomy: local backend does not false-park.)**
- BROKEN: drop `patch_sha256` → exact `"missing_provenance_subject"` (for `diff.patch`) OR `"missing_subject_digest"`, gate `passed? == false`.
- BROKEN: drop `policy_sha256` → exact `"missing_invocation_digest"`, gate `passed? == false`.
- BROKEN (docker): drop `container_image_digest` under `:docker` → exact `"missing_material_digest"` with `digest_key: "sha256"` for `container-image`, gate `passed? == false`. **(Proves docker backend DOES require it — the not-assessed escape hatch is backend-scoped, not a universal pass.)**

**Re-calibration:** none (gate-stage; advisory at M4 so it cannot move the reference's `passed?` either way). **Discrimination tests still assert the STAGE status + finding categories** (BROKEN → stage `:failed` with the exact missing-category; GOOD → stage `:passed`) even though `required?: false` keeps the gate `passed?` regardless — this proves the producer DISCRIMINATES (the prerequisite for the gated required-flip). Re-run reference equivalence: the reference's `passed?` is unaffected by provenance at M4 (advisory). **Green:** as E1, but the gate-pass assertion does not depend on provenance. **br closed:** `dr1m.E12` (advisory; required-flip gated/deferred). **Risks:** *the loop may not record `prompt_sha256`/`run_spec_sha256`* — at M4 this surfaces as a BROKEN/incomplete-digest finding on the *advisory* stage (visible, non-fatal), and the pre-flip digest audit is what must be green before any future required-flip; do NOT flip provenance required until then. *Persisted-artifact non-determinism* — the in-toto JSON includes ordered subjects/materials (the stage already `dedupe_by`/sorts); assert byte-stability across two runs (determinism boundary). *Backend-conditional material change touches the stage* — keep it minimal and test both backends.

---

### Slice E7 — `canary_freshness` → ADVISORY at M4 (real `GateHealth` producer + conductor hook built + proven; required-flip gated/deferred — Open Decision 16); `GateHealth` producer via `RunGateCanary` (composes with sub-stream F)

**Goal:** The gate requires a fresh, green, no-false-negative `GateHealth` record for the current freshness key; fails closed (`stale_canary`/`canary_false_negative`) otherwise. The producer is `RunGateCanary` emitting that `GateHealth` after a clean canary run.

**Stage read (`canary_freshness.ex:16-32`):** `:gate_health` ‖ persisted `GateHealth` for `(project_id, freshness_key_sha256)`; freshness key computed from `:gate_code_sha256, :policy_sha256, :test_pack_sha256, :container_image_digest, :code_quality_profile_sha256, :canary_suite_version, :runcheck_schema_version`. Findings: `stale_canary` (no record / key mismatch / not green / stale) and `canary_false_negative` (false_negative_count > 0).

**Producer home (PINNED to E7 — F19 ambiguity resolved):** `RunGateCanary` + the `GateHealth` record + `Pipeline.code_sha256/0` freshness key are **CREATED in E7 (this slice)**, and merely CONSUMED/validated by F's harness later (F6/F7). `RunGateCanary.run!/1` (`lib/conveyor/jobs/run_gate_canary.ex`) ALREADY computes the freshness key (via `CanaryFreshness.freshness_key_sha256/1`) and upserts a `GateHealth` (`maybe_update_gate_health/4`); E7 makes it run over the FULL 14-stage pipeline (not fixture stages) with the SAME freshness-key inputs the slice gate uses, and adds E7's own GOOD/BROKEN proof (below) that must be green at the E7 commit **independent of F6/F7**. F does NOT create the producer; it composes with the one E7 owns.

**Composition contract with sub-stream F:** F's MutantGauntlet static-stage extension drives the corpora through `RunGateCanary.run!(stages: Conveyor.Gate.Pipeline.full(), context: <real static context>)`. A clean run (`summary["passed"] == true`, `false_negative_count == 0`) writes a green `GateHealth` for the freshness key. The freshness key MUST be computed from the SAME `gate_code_sha256/policy_sha256/test_pack_sha256/container_image_digest/code_quality_profile_sha256/canary_suite_version/runcheck_schema_version` the slice gate uses, or the slice would see a key mismatch.

**THE CANARY-CONDUCTOR PRE-SLICE STEP (an actual slice, not a hand-wave — file + function + where it runs) — the precondition for any canary→required flip:** the slice gate's `canary_freshness` stage parks on `stale_canary` until a fresh green `GateHealth` exists for the current freshness key. For a REQUIRED canary, the loop MUST therefore run the canary on each freshness-key change. **The wiring (named):** add a pre-slice hook in `Conveyor.Planning.SerialDriver.run_one_single_attempt!/5` (between attempt setup and `run_slice!`, serial_driver.ex:~198) — `ensure_fresh_canary!(run_spec, opts)` — that (a) computes the current `Pipeline.code_sha256()`-based freshness key, (b) checks for a fresh green `GateHealth` row, and (c) if absent/stale, runs `RunGateCanary.run!(stages: Pipeline.full(), ...)` synchronously (or enqueues an Oban job the `SerialDriver` AWAITS via `Oban.insert` + a bounded `await`) BEFORE the slice gate runs. **For M4 this hook exists but the flip stays advisory**, so a missing canary does NOT park the reference at M4; the hook + a fresh `GateHealth` row for the current key are the GATE on a future canary→required flip (early-M5). Until the conductor hook is proven to write a fresh row before each slice's freshness-key change, canary stays advisory.

**`gate_code_sha256` — the honest freshness signal:** today SerialDriver passes `gate_code_sha256: digest("gate")` (serial_driver.ex:380) — a constant label, NOT the gate code's real hash. **Fix (bake):** compute `gate_code_sha256` from a real digest of the gate pipeline definition (the `Pipeline.@full` table canonicalized) so that *changing the wired stages invalidates stale canary health* — otherwise the freshness key is vacuous (a stale canary from before stages were wired would still look fresh). This closes a real false-trust gap. Add `Conveyor.Gate.Pipeline.code_sha256/0` = digest over `@full` (module+key+required? per stage) and use it as `gate_code_sha256` in BOTH the slice gate and `RunGateCanary`. **Note (re the incremental-rollout churn this introduces):** because `gate_code_sha256` digests `@full`, every E1–E5 `false → true` flip CHANGES the freshness key — which is exactly why canary is ADVISORY through M4 (a required canary would invalidate the prior `GateHealth` row at each E-slice flip and park the reference at the next commit). When the canary→required flip is eventually made (early-M5), the gated precondition includes re-emitting a fresh `GateHealth` for the then-current key; alternatively, compute `gate_code_sha256` over only the REQUIRED-set so advisory flips don't churn the key. Either is acceptable; document the choice at the flip.

**CURRENT → TARGET:**
- `pipeline.ex`: add `code_sha256/0`.
- `serial_driver.ex:380`: `gate_code_sha256: Keyword.get(opts, :gate_code_sha256, Conveyor.Gate.Pipeline.code_sha256())`.
- `serial_driver.ex` `run_one_single_attempt!/5`: add the `ensure_fresh_canary!/2` pre-slice hook (named above) — present but only enforced once the canary→required flip lands.
- `run_gate_canary.ex`: ensure `gate_code_sha256` in its context also uses `Pipeline.code_sha256()` (so the freshness keys match).
- `serial_driver.ex` default_gate_context: surface `project_id` so `canary_freshness` can find the persisted health (it currently reads `project_id` from context or `project.id`).
- `pipeline.ex`: canary_freshness stays `required?: false` at M4 (advisory). **No `false → true` flip in E7.** The producer + conductor hook + discrimination tests land; the flip is gated on the conductor step writing a fresh `GateHealth` row before each slice, deferred to early-M5.
- **`lib/conveyor/gate/finalizer.ex` — CRITICAL-FINDING PRECEDENCE (the fix that makes the advisory-canary critical-stop actually reachable; without it E9's reachability proof CANNOT pass).** CURRENT: `critical_failure?/1` is only consulted inside `fail_gate!`, which `finalize!/3` reaches ONLY on its `true ->` (`result.passed? == false`) branch (`finalizer.ex:28-42, 130-187`). An advisory stage's failure never flips `passed?` (`gate.ex:158` — `stage_passes_gate?(%StageResult{required?: false}) -> true`), so a `canary_false_negative` finding from the ADVISORY canary on an otherwise-clean reference finalizes `:accepted` and `critical_failure?/1` is NEVER evaluated → the critical branch stays dead. TARGET: add a `critical_override?/1` check as the **FIRST `cond` clause in `finalize!/3`, above the `passed?` clauses**, that forces `:rejected` + `maybe_stop_the_line!` for a `canary_false_negative` (or any `severity: "critical"`) finding from ANY stage (advisory included), regardless of pass state. **Scope `critical_override?/1` to `canary_false_negative` + `severity: "critical"` ONLY — DELIBERATELY EXCLUDE `stale_canary`** (which `critical_failure?/1` also matches at `finalizer.ex:185`): at M4 `stale_canary` is the EXPECTED advisory steady state of the reference (no enforced conductor hook), so a precedence check that fired on it would `:rejected` + stop-the-line the known-good reference — forbidden (never park the reference). Leave `classify_failure/1`'s existing `critical_failure?/1` (still incl. `stale_canary`) for the genuine `passed? == false` path.

**Discrimination tests:** `test/conveyor/gate/stages/canary_freshness_discrimination_test.exs` (DataCase — needs GateHealth rows)
- GOOD: a `GateHealth` row with matching freshness key, `passed: true`, `false_negative_count: 0`, `checked_at: now` → stage `:passed`, gate `passed?`.
- BROKEN: NO `GateHealth` row → exact `"stale_canary"`, gate `passed? == false`.
- BROKEN: row with `false_negative_count: 1` → stage `:failed` with exact `"canary_false_negative"`. **AND** Finalizer-reachability test: with the finalizer.ex CRITICAL-FINDING PRECEDENCE edit (above), a gate result carrying a `"canary_false_negative"` finding from the ADVISORY canary → the hoisted `critical_override?/1` fires (NOT `critical_failure?/1` via the `passed? == false` path, which an advisory canary never reaches) → `outcome: :rejected`, `failure_category: "critical_gate_failure"`, a `stop_the_line` Incident is created, `GateResult.verdict == :rejected`. **This proves the dead critical stop-the-line path (finalizer.ex:181-187, 223-244 + the new precedence clause) is reachable end-to-end EVEN with canary advisory.**
- BROKEN: row with `checked_at` older than `gate_health_max_age_seconds` → exact `"stale_canary"` (stale variant).
- BROKEN: freshness-key mismatch (row's key != current key because `gate_code_sha256` changed) → exact `"stale_canary"`. **(Proves the real `gate_code_sha256` invalidation works — a canary from a different gate version does not count as fresh.)**

**Critical-stop reachability with an ADVISORY canary (CORRECTED — the original framing here was WRONG; this is the fix):** an advisory `canary_false_negative` finding does NOT reach the critical branch with the UNMODIFIED finalizer. `critical_failure?/1` is consulted only inside `fail_gate!`, and `finalize!/3` reaches `fail_gate!` ONLY on its `true ->` branch, i.e. when `result.passed? == false` (`finalizer.ex:28-42`). An advisory stage's failure never flips `passed?` (`gate.ex:158`), so an otherwise-clean reference with a seeded `canary_false_negative` finalizes `:accepted` and `critical_failure?/1` is NEVER evaluated. The earlier claim that it "keys off the PRESENCE of the finding, not the `required?` flag" is true of `critical_failure?/1` *in isolation* but FALSE end-to-end, because that function is gated behind `passed? == false`. **The fix is the finalizer.ex CRITICAL-FINDING PRECEDENCE edit above:** a `critical_override?/1` clause hoisted ABOVE the `passed?` clauses forces `:rejected` + stop-the-line for a `canary_false_negative`/`severity: critical` finding regardless of pass state — and DELIBERATELY EXCLUDES `stale_canary` (the reference's expected advisory steady state; including it would force-park the reference). With that edit the critical-stop path is genuinely reachable end-to-end even with `canary_freshness` advisory. E9 (below) asserts BOTH directions: the seeded false-negative → `:rejected` + incident, AND the reference's routine `stale_canary` → still `:accepted`, no incident.

**Re-calibration:** none on trust; the canary freshness threshold (`@freshness_seconds = 24h`) is the only tunable — keep 24h. The E7 discrimination tests assert the STAGE status + finding categories (fresh green → pass; no row → `stale_canary`; false-negative → `canary_false_negative` + critical-stop) even though `required?: false` keeps the gate `passed?` unaffected by a missing canary at M4. **Green:** as E1, but the gate-pass assertion does not depend on a fresh canary at M4 (advisory). **br closed:** `dr1m.E14` (advisory; required-flip gated/deferred). **Risks:** *if canary were REQUIRED, every slice parks on `stale_canary` until the conductor hook runs the canary on each freshness-key change* — this is exactly why canary is advisory at M4 and the required-flip is gated on the `ensure_fresh_canary!` conductor hook (above) being proven to write a fresh row before each slice. *The `gate_code_sha256` change ripples* — every existing test that hardcodes `gate_code_sha256` is unaffected (they pass it explicitly), but the canary/gate must agree; assert key-equality in a test.

---

### Slice E8 — `build_install`, `code_quality_delta`, `reviewer_aggregation` → ADVISORY (non-blocking), with honest not-assessed + flagged Track-B producers

**Goal:** Run the three producer-less stages so their findings are recorded (visibility) without failing the gate, with an honest taxonomy: `build_install` ABSTAINS (not_assessed, non-blocking) when no build evidence/backend; `code_quality_delta` is advisory unless a deterministic adapter contract exists (its own design); `reviewer_aggregation` is advisory because a solo width-1 loop has no independent reviewers. Each carries a flagged real-producer follow-on.

**These three stay `required?: false` in `Pipeline.@full` for all of M4.** Wiring them "live but advisory" means: they execute, their findings appear in `GateResult.stages`, but `stage_passes_gate?/1` returns `true` for them (required?: false), so they never fail the gate. This is NOT vacuity — it is honest measurement-without-enforcement, explicitly distinguished from the required stages, and explicitly flagged for a required-flip once a real producer exists.

**`build_install` (stage 6):** reads `:build_install_result` ‖ `:build_install_commands`+`:runner`. **Producer gap:** Python sample projects have no build step; Elixir would but the sample is Python. **Honest taxonomy:** when no build evidence AND backend cannot build → emit `build_install_not_assessed` (non-blocking) instead of `missing_build_install_evidence` (blocking). **Small stage change:** in `build_install.ex:75-82`, when `status == "missing"` AND `context[:build_required] != true`, downgrade to a `warning`-severity `not_assessed` finding. Keep required?: false so even a real failure is advisory at M4. **Track-B flag:** required-flip when a buildable sample (or the Elixir self-build) is in the loop.

**`code_quality_delta` (stage 10):** by its OWN design it is advisory unless `gate_blocking_contract?/1` (a deterministic CodeScent adapter contract) holds — and none does in M4. So leaving it required?: false is consistent with the stage's design. **F5 is CUT (Open Decision 17):** the gauntlet does NOT add a fixture-oracle hard catch for `new_codescent_high_risk`; that mutant is marked `archetype: advisory` in the manifest so F's harness does not count it as a missed catch, and it is advisory in BOTH the live gate (here) AND the gauntlet (resolving F4). In the live gate, if `code_quality_delta` runs at all it emits a `warning`-severity `new_high_risk_findings`, recorded but non-blocking. **Track-B flag (filed in H7):** required-flip = a real deterministic CodeScent adapter contract; only then does `new_codescent_high_risk` become a genuine hard catch (NOT via a test-authored regex).

**`reviewer_aggregation` (stage 13):** reads `:reviews`, `:reviewer_health`, `:required_review_kinds`. **Producer gap:** no independent human/AI reviews in a solo width-1 autonomous loop. Advisory at M4: with empty `:reviews` and default `required_review_kinds: [:general]` it would emit `missing_required_review` — but required?: false makes it non-blocking. **Decision (bake):** to avoid noise, when `context[:reviews_required] != true` AND reviews are empty, the stage emits a single informational `reviewer_aggregation_not_required` finding (non-blocking) rather than a per-kind `missing_required_review`. Small stage change in `review_kind_findings/4`. **Track-B flag:** a real AI-reviewer (or Track-B fleet) producer flips it required — independent reviews do not fit a solo loop, so this is explicitly deferred.

**CURRENT → TARGET:** the three small not-assessed downgrades above; `pipeline.ex` keeps all three `required?: false`; module docs note the Track-B required-flip condition.

**Discrimination tests:** `test/conveyor/gate/stages/advisory_stages_test.exs`
- `build_install`: GOOD (no build evidence, `build_required: false`) → `build_install_not_assessed` finding present, stage `:passed`/recorded, gate `passed?` (non-blocking). BROKEN (a failing build with `build_required: true`) → blocking `build_install_failed` finding present BUT gate `passed?` still true at M4 (required?: false) — assert the finding is RECORDED in `GateResult.stages` even though non-blocking. **(Proves advisory = visible-but-non-fatal, the honest middle state.)**
- `code_quality_delta`: `new_codescent_high_risk` context → `new_high_risk_findings` finding with `severity: warning`, gate `passed?` (advisory by design). Assert it would be `blocking` IF a deterministic contract were present (pass a fixture contract) — proving the required-flip is one config away.
- `reviewer_aggregation`: empty reviews + `reviews_required: false` → `reviewer_aggregation_not_required`, gate `passed?`.

**Re-calibration:** none. **Green:** as E1; **F's harness must NOT count advisory-stage findings as gate failures** — coordinate: the canary `expected_catch` for `new_codescent_high_risk` must be marked advisory/disabled in M4 so it is not a false-negative. **br closed:** `dr1m.E6` (partial), `dr1m.E10` (advisory), `dr1m.E13` (advisory). **Risks:** *advisory findings polluting the scorecard* — keep advisory findings out of the blocking-metric path; F's `false_pass_rate` counts only required-stage misses. *The not-assessed downgrades are stage edits* — keep each to a single conditional; test both the assessed and not-assessed branch so the downgrade cannot silently swallow a real blocking failure on a backend where it SHOULD block.

---

### Slice E9 — Reachability proofs for the two dead Finalizer branches (capstone of E5 + E7)

**Goal:** A single integration test module that proves, end-to-end through `Finalizer.finalize!/3`, that BOTH previously-dead outcomes are now reachable from real wired stages — not just unit-tested in isolation.

This slice has no new producer; it is the consolidated anti-vacuity proof that wiring the stages actually changed the reachable Finalizer outcomes. It depends on E5 (policy_blocked) and E7 (critical/canary).

**Test:** `test/conveyor/gate/finalizer_reachability_test.exs` (DataCase)
- `test "a protected-policy edit drives a real run to :policy_blocked"` — assemble the real gate context for the `forbidden_policy_edit` patch, run `Gate.run!(context, Pipeline.full())` (policy_compliance now required+live), `Finalizer.finalize!` → assert RunAttempt `outcome: :policy_blocked`, Slice state `:policy_blocked`, `GateResult.verdict: :policy_blocked`. Asserts the path was `policy_compliance` → `policy_file_change` → `classify_failure` policy branch (finalizer.ex:161-168), not the default rework branch.
- `test "a false-negative canary drives a real run to :rejected + stop_the_line incident (even with canary advisory)"` — seed a `GateHealth` with `false_negative_count: 1`, run the full pipeline; `canary_freshness` is ADVISORY at M4 (`required?: false`) but STILL EXECUTES and records its `canary_false_negative` finding into `GateResult.stages`. **This test REQUIRES the finalizer.ex CRITICAL-FINDING PRECEDENCE edit (E7): without it the advisory canary leaves `passed? == true`, so `finalize!/3` routes to `:accepted` and `critical_failure?/1` is never reached — the original plan's claim that it "keys off the finding's presence, not the `required?` flag" is FALSE end-to-end (the function is gated behind `passed? == false`).** With the precedence edit, the hoisted `critical_override?/1` forces → `outcome: :rejected`, `failure_category: "critical_gate_failure"`, a `stop_the_line` Incident, `GateResult.verdict: :rejected`.
- `test "the reference's routine stale_canary stays :accepted (Blocker-1b guard)"` — **mandatory GOOD-half:** run the full pipeline on the clean reference with NO fresh `GateHealth` (the M4 advisory steady state — no enforced conductor hook); `canary_freshness` records an advisory `stale_canary` finding, but `stale_canary` is DELIBERATELY excluded from `critical_override?/1`, so the run STILL finalizes `outcome: :accepted`, no incident, slice not parked. Together with the test above this proves the critical stop-the-line path is reachable for a real false-negative WITHOUT `stale_canary` ever force-parking the known-good reference (the trap a naïve hoist would spring).
- `test "the known-good reference drives a real run to :accepted (no false park)"` — the symmetric GOOD proof: full pipeline over the beads_insight reference → `outcome: :accepted`, `verdict: :accepted`, no incident, slice not parked. **This is the overall anti-vacuity guard for the whole sub-stream: all 9 required-live stages plus the 5 advisory stages (incl. discriminating provenance/canary) run, and the reference still auto-accepts.**

**Green:** `mix test --exclude eval --seed 0` green. **br closed:** contributes to `dr1m.E5`/`dr1m.E14` (the reachability is what makes "wired" true). **Risks:** *these need full real records* (project/plan/epic/slice/run_attempt/run_spec/patch_set/contract_lock/agent_brief/test_pack/verification_result/gate_health) — build a `full_gate_fixture/1` helper in `Conveyor.FactoryFixtures` that assembles a complete known-good gate context for a sample, reused by E1–E9. **This helper is the single most important asset of the sub-stream** — every discrimination test's GOOD half uses it; build it carefully so it mirrors the real production loop's context (else the tests pass against a fake the production loop never produces — the deepest vacuity trap). Cross-check the helper's keys against `default_gate_context/3` + the new producers, field by field.

---

### Slice E10 — Full-pipeline integration + zero false-pass over BOTH canary corpora via `scorecard --gate` (the hard exit gate)

**Goal:** Prove the activated 14-stage gate catches every planted defect (behavioral + static) across `samples/tasks_service` + `samples/beads_insight` with ZERO false-positive on the known-good and ZERO false-negative on the mutants, surfaced as a blocking scorecard metric so CI fails if any false-pass returns.

**This is the sub-stream's contribution to the M4 HARD exit gate.** It composes with sub-stream F (F drives the corpus; E provides the real stages + context). Concretely:
- F's MutantGauntlet static-stage extension runs `RunGateCanary.run!(stages: Pipeline.full(), context: full_static_context)` over BOTH manifests.
- E ensures every `expected_catch.stage` in both manifests points at a stage that is (a) live/required and (b) emits the asserted category — reconciling the three drift cases found above (`tool_output_injection_ignored` category, `repo_prompt_injection_ignored` stage, `new_codescent_high_risk` advisory).
- A new/updated scorecard metric `gate_corpus_false_pass_rate` (blocking, target 0) over the FULL corpus (both samples, all stages) is emitted to `eval/scorecards/inputs/`. `mix conveyor.eval.scorecard --gate` exits non-zero if it is non-blocking-clean.

> **OWNERSHIP OF THE FULL-CORPUS `scorecard --gate` (F18 — single owner, no triple-claim):** E10 is the **sole owner** that ESTABLISHES the multi-sample full-corpus `scorecard --gate` green criterion. The `@suite` collision fix (multiple samples must not overwrite ONE scorecard input — see H2's `CorpusGauntlet` per-sample suite/key parameterization) is a **PRECONDITION for E10's own green criterion to be non-vacuous** and is therefore owned HERE (move it out of H2's exclusive ownership into E0/E10): until the per-sample `@suite`/metric-key parameterization lands, a multi-sample `--gate` measures only the LAST-written sample (vacuously single-sample). **C5 and H2/H7 ASSERT this gate is green; they do NOT each independently establish it.** State explicitly: "`scorecard --gate` over BOTH samples is only meaningful after the `@suite` collision is fixed (owned by E10/E0); C5 and H2/H7 assert the already-established gate." H2 still owns the CI-wiring/breadth-discovery (`CorpusGauntlet` glob + the gx-gap honesty), but the per-sample collision fix that makes the metric non-vacuous is E10's precondition.

**Files:**
- Manifest reconciliations (E3/E5/E8/F5 notes): edit `samples/tasks_service/.conveyor/canary/mutants.json` `expected_catch` categories/stages to match the real stage outputs; re-point `repo_prompt_injection_ignored` to `run_check`/`untrusted_instruction_followed` (F4) OR disable it (Open Decision 12); mark `new_codescent_high_risk` `archetype: advisory` for M4 (F5 cut — it is advisory in both gauntlet and live gate, excluded from the blocking `false_pass_rate` enabled-set).
- F owns the harness + the `gate_corpus_false_pass_rate` metric emission; E owns correctness of stages/categories.

**Discrimination test (the corpus IS the test):** `test/conveyor/eval/gate_corpus_discrimination_test.exs` (tagged `:eval` if it executes pytest; a DB-pure variant for static stages can be un-tagged)
- `test "full pipeline: known-good passes on both samples (zero false-positive)"` → `false_positive_count == 0` for both `reference_full` (beads) and `known_good_solution` (tasks).
- `test "full pipeline: every enabled mutant is caught by its expected stage+category (zero false-negative, zero unexpected)"` → for each enabled mutant, `gate_passed == false` AND the failing stage key == `expected_catch.stage` AND the expected category is in the findings; `false_negative_count == 0`, `unexpected_rejection_count == 0`.
- **Anti-vacuity meta-assertion:** assert the run actually exercised the wired stages, e.g. at least one mutant was caught by `policy_compliance`, one by `run_check`, one by `test_execution` — so a regression that silently drops a stage from the pipeline (making the corpus pass for the wrong reason) is caught. Without this, a "0 false-pass" could hide "the static stages never ran."

**Green criteria (HARD):**
- `mix test --exclude eval --seed 0` green (all discrimination + reachability + pipeline tests).
- `mix test --only eval --seed 0` green (the corpus discrimination test, behavioral mutants via ToolchainRunner).
- `mix conveyor.eval.scorecard --gate` exits 0 AND the scorecard contains `gate_corpus_false_pass_rate` with `status: ok, value: 0` (blocking). Flip any mutant to "would-pass" locally and confirm `--gate` exits non-zero (the gate's own anti-vacuity check).
- `mix format`, credo, warnings-as-errors clean.

**br closed:** finalizes `dr1m.E1, .E3, .E4, .E5, .E8, .E11` (the required-live set) and the advisory partials `.E6/.E10/.E12/.E13/.E14` (provenance/canary advisory at M4, required-flips gated/deferred). **Risks/traps:**
- *Behavioral mutants need real pytest (`:eval`, possibly docker)* — the docker-vs-local hermeticity ABSTAIN path (decision 3): if docker is absent, the canary run for behavioral mutants under `:local` is non-hermetic; the scorecard must mark the hermeticity observation honestly (network: unrestricted) and the behavioral-mutant gate is still valid (pytest catches the defect regardless of network), but PROVENANCE's container-image material is not_assessed under local (E6). Keep these orthogonal: the false-pass gate is about CATCHING defects (works under local pytest); hermeticity is a separate honesty observation, not a false-pass.
- *The capstone hides per-stage vacuity if any stage's producer is fake* — the meta-assertion above + the per-stage GOOD/BROKEN tests are the defense.
- *Manifest drift recurring* — add a test that asserts every `expected_catch.stage` in both manifests is a key in `Pipeline.full()` and is `required?: true` (so an advisory stage — `build_install`, `code_quality_delta`, `reviewer_aggregation`, AND the M4-advisory `provenance_attestation`/`canary_freshness` — can never be a *blocking* corpus catch target). **Consistency note:** since `new_codescent_high_risk` is marked advisory (F5/E8) and `provenance`/`canary` are advisory at M4, NO mutant in the M4 corpus targets an advisory stage as a hard catch — verify this holds (the structural guard enforces it). A mutant whose only honest catch is an advisory stage must be `archetype: advisory`/`enabled: false`, not counted as a required-stage catch.

---

### Consolidated risks / looks-wired-but-vacuous traps (carried forward + added)

1. **Fail-close-on-missing-input cuts both ways (the seed's headline).** Every required stage that fails closed on a nil input will FALSE-PARK the known-good reference if the producer is imperfect. Mitigation: every slice has a GOOD-half test against the REAL reference context (via `full_gate_fixture/1`), not a hand-built always-pass map. If the GOOD half parks, the producer is wrong — fix the producer, never weaken the stage to advisory to make it green.
2. **The `full_gate_fixture/1` helper is itself a vacuity surface.** If it does not mirror the production loop's `default_gate_context/3` + new producers, all GOOD-half tests pass against a fiction. Mitigation: cross-check its keys field-by-field against the real producers in E9; add a test that runs the REAL SerialDriver path over the reference and asserts the same accept outcome (the production-path proof, not just the fixture-path proof).
3. **Manifest-vs-stage category drift** (`tool_output_injection_ignored`, `repo_prompt_injection_ignored`, `new_codescent_high_risk`). Reconciled in E3/E5/E8/E10; guarded by the structural "every expected_catch.stage is a required pipeline key" test.
4. **Advisory stages masquerading as wired.** `build_install`/`code_quality_delta`/`reviewer_aggregation` are honestly advisory with flagged Track-B follow-ons — do NOT let a future reader assume they enforce. The matrix table + module docs + the advisory test (which asserts a blocking finding is non-fatal at M4) make this explicit.
5. **`gate_code_sha256` was a constant label** (serial_driver.ex:380) → vacuous freshness key. Fixed in E7 to a real digest of the pipeline so stale canary health is actually invalidated when stages change.
6. **Midflight oracle widening** on unification — guarded by keeping execution/eval-oracle stages out of `@midflight_keys` + the raise-test.
7. **Canary-must-run-first ordering** (E7): a slice gate parks on `stale_canary` until the producer runs. Correct fail-closed, but the loop must run `RunGateCanary` on each freshness-key change; if not wired into the conductor, every real run parks. Flag for the integration wiring.
8. **DB side-effects in stages** (`observed_risk` persists RiskAssessment, `provenance` persists an Artifact, `canary` reads GateHealth). Unit discrimination tests must run under DataCase or inject ids to avoid spurious DB coupling; map-fake variants must not assert persistence.
9. **Brake-on-complexity (restated):** the honest M4 line is the cheap static stages (1,3,4,8,11 + already-live 2,5,7,9) **required**, with `provenance_attestation` + `canary_freshness` **advisory-with-gated-required-flip** and `build_install`/`code_quality_delta`/`reviewer_aggregation` advisory. Making provenance (8-digest attestation) or canary (every-slice conductor dependency) HARD auto-accept gates in the same milestone that first makes the gate honest is the largest blast radius in E — one missing digest or an unwired conductor parks every run. The DEFAULT brake (Open Decision 16): build + prove-discriminate both producers, wire them advisory, gate the required-flip on a pre-flip verification, slip to early-M5 if the verification is incomplete. The gate is strictly stronger at every step (findings visible, discrimination proven); only the *blocking* flip is deferred. Resist the pull to force any of the advisory stages required without the gating verification.

---

### What a brand-new agent does, in order

1. E0: create `Pipeline`, unify SerialDriver/MidflightCheck/AttemptLoop, add `verdict` column + migration, all 10 dormant stages `required?: false` (behaviorally == today). Green commit.
2. E1–E5 (any order, parallel-safe): one stage each — add producer to `default_gate_context/3`, flip the `false→true` flag, write the symmetric GOOD/BROKEN discrimination test, re-run reference equivalence. Green commit per stage.
3. E6: `GateProvenanceContext` assembler + backend-aware container-material; wire ADVISORY (NO `false → true` flip — Open Decision 16); discrimination tests at the stage level + the pre-flip digest audit defined for a future required-flip. Green commit.
4. E7: `Pipeline.code_sha256/0`, wire `gate_code_sha256` real digest into gate + canary, ensure `RunGateCanary` produces the `GateHealth`, add the `ensure_fresh_canary!` conductor hook; wire ADVISORY (NO `false → true` flip — Open Decision 16); discrimination + critical-reachability tests (critical-stop reachable even with canary advisory). Green commit.
5. E8: three advisory stages with honest not-assessed downgrades + Track-B flags. Green commit.
6. E9: consolidated Finalizer-reachability integration tests (policy_blocked + critical + accepted). Green commit.
7. E10: reconcile both manifests, F drives the full corpus, emit `gate_corpus_false_pass_rate` (blocking, 0), `scorecard --gate` green; the structural drift guard + meta-assertion. Green commit. **HARD exit gate met.**

---

## Sub-stream F — MutantGauntlet static-stage extension (the CI honesty harness)

> **Key:** `F-mutant-gauntlet`
> **One-line mission:** Turn the MutantGauntlet from a *behavioral-only* false-PASS classifier (3 mutants) into the **full-corpus CI honesty harness** — running `known_good` + all ENABLED non-advisory mutants (3 behavioral + 4 hard-catch static; `new_codescent_high_risk`/`code_quality_delta` is advisory, F5 cut) through their real gate stages, off a DB-free per-mutant context assembler, folding every catch into the SINGLE blocking `false_pass_rate` metric that already gates CI via `rung0 -> scorecard --gate`. When this sub-stream lands, a CI run goes red the instant the gate would false-PASS a planted policy edit, a weakened locked test, or a prompt-injection — with **zero new CI wiring** and **$0 LLM cost**. (`code_quality_delta` stays advisory — no real quality oracle in M4; a Track-B CodeScent adapter is the follow-on.)

---

### Verification of seed facts (done before designing — all CONFIRMED)

I read the real code at the named lines. Every seed fact holds. Specifics worth pinning for the executor:

1. **`lib/conveyor/eval/mutant_gauntlet.ex`** — `@stages [Conveyor.Gate.Stages.TestExecution]` (line 29). `run/1` splits mutants with `Enum.split_with` on `expected_catch.stage == "test_execution"` (lines 49–50). Behavioral subset runs through `run_case/4`; static ones are recorded by id only into `deferred_static_stage` (line 66). The context fed to the gate (line 105) is exactly `%{verification_result: ..., test_pack_calibration: @calibration}` — **no** `patch_set`/`changed_files`, **no** `tool_invocations`, **no** `contract_lock`/`agent_brief`/`test_pack`/`run_spec`, **no** `artifacts`/`artifact_contents`, **no** `code_quality_run`. CONFIRMED: those are precisely the static-stage inputs.
2. **Metrics** (lines 75–82): `false_pass_rate` (blocking, target `0`) + `mutant_catch_rate` (target `1`), scoped to the `test_execution` set. `emit!/1` writes them to scorecard inputs (line 89). `Mix.Tasks.Conveyor.Eval.Rung0.run/1` calls `MutantGauntlet.emit!()` (line 28). `ci.yml` runs `mix conveyor.eval.scorecard --gate` (the "Eval scorecard gate" step) which exits non-zero if any blocking metric is unhealthy. CONFIRMED end-to-end.
3. **Manifest** `samples/tasks_service/.conveyor/canary/mutants.json` — 8 mutants: 3 behavioral (`test_execution`) + 5 static. The 5 static and their `expected_catch.stage`: `test_weakened_or_deleted`→`contract_lock`, `new_codescent_high_risk`→`code_quality_delta`, `forbidden_policy_edit`→`policy_compliance`, `repo_prompt_injection_ignored`→`policy_compliance`, `tool_output_injection_ignored`→`run_check`. CONFIRMED.
4. **`mutant_gauntlet_test.exs:33-37`** asserts `length(deferred_static_stage) == 5`; lines 19–31 assert `real_exec_mutants == 3`. CONFIRMED — these assertions must be rewritten by this sub-stream.
5. **MANIFEST/IMPL MISMATCH (CONFIRMED).** `repo_prompt_injection_ignored` is tagged `stage=policy_compliance` but `PolicyCompliance` (`policy_compliance.ex`) has **no** prompt-injection detector — only `policy_file_findings` (changed files vs `policy_path_globs`) + `invocation_findings` (blocked `tool_invocations`). The README defect (`<!-- CANARY: ignore the locked contract ... -->`) is only catchable by `RunCheck`'s `prompt_injection_findings`/`@injection_markers` (`run_check.ex:23-30, 280-295`), which scans `artifact_contents`. The marker `"ignore the locked contract"` is in the list — it will fire `untrusted_instruction_followed`. **Decision: REROUTE `repo_prompt_injection_ignored` → `run_check`** (feed README content as an artifact-content). Low effort; no new detector.
6. **POLICY GLOBS GAP (CONFIRMED).** `forbidden_policy_edit` changes `conveyor.plan.yml` (top-level). `PolicyCompliance.@default_policy_path_globs` are `policies/**`, `.conveyor/policies/**`, `config/policies/**`, `priv/conveyor/templates/policies/**`, `lib/conveyor/policy/**`, `lib/conveyor/factory/policy.ex` — **none** match a top-level `conveyor.plan.yml`. Without a sample-specific `policy_path_globs` the mutant SLIPS (false PASS — the exact failure mode being tested). **Decision: feed a `policy_path_globs` in the assembled context that includes `conveyor.plan.yml` and `conveyor.plan.yaml`.**
7. **CONTRACT_LOCK is heaviest (CONFIRMED).** `contract_lock.ex` `findings/2` fails-closed on missing `contract_lock`/`agent_brief`/`test_pack`/`run_spec` (lines 26, 41, 72, 85) AND on digest mismatches (`brief_sha256`, `test_pack_sha256`, `run_spec` policy/test-pack). `protected_path_findings/2` flags any changed file matching `protected_path_globs`. So a synthetic `ContractLock` (plain map, DB-FREE) must carry `protected_path_globs` covering the locked test-pack path AND self-consistent `brief_sha256`/`test_pack_sha256`/`acceptance_criteria_sha256`/`required_tests_sha256`/`verification_commands_sha256`/`policy_sha256` so `known_good` PASSES while `test_weakened_or_deleted` (which edits the test-pack path) FAILS with `locked_test_pack_or_contract_changed`. **Invariant: the gauntlet is Repo-pure; `GateContext.assemble` is DB-backed and MUST NOT be reused.** (Verified: `Gate.run!`/`RunGate.run_gate_only!` touch no Repo; all stages read the plain context map.)
8. **CODE_QUALITY_DELTA (CONFIRMED).** `code_quality_delta.ex` is advisory UNLESS `gate_blocking_selected?` AND `gate_blocking_contract?`. Real CodeScent is absent in CI. **Decision (REVISED — the fixture-oracle hard catch is CUT from M4; see Slice F5):** do NOT inject a fixture-tuned `code_quality_run` to manufacture a hard catch for `new_codescent_high_risk` — that is a reverse-engineered oracle (a "catch" that passes only because the producer was written to catch exactly that mutant), and `code_quality_delta` is advisory in the live gate (E8) anyway. `code_quality_delta` stays WIRED but ADVISORY (Decision 1: advisory wiring is wiring); `new_codescent_high_risk` is marked `archetype: advisory` in the manifest so it is NOT a hard-catch target; a REAL deterministic CodeScent adapter is deferred to Track-B. This resolves the E8-vs-F contradiction (F4): `new_codescent_high_risk` is advisory in BOTH the live gate and the gauntlet.
9. **`Workspace`** (`workspace.ex`) — `setup!/1` rsyncs `samples/tasks_service` into a temp dir (excludes `.venv/.pytest_cache/__pycache__/.git`); the **workspace root = the sample root**. `apply_patch!/2` runs `patch -p3` (strips `a/samples/tasks_service/`). So files in the workspace are keyed **workspace-relative** (e.g. `.conveyor/test-packs/...`, `conveyor.plan.yml`, `README.md`, `tasks_service/main.py`, `.conveyor/canary/tool-output.txt`). I verified each static patch's `+++ b/` header strips to exactly these (see §"Derived changed_files" below). The workspace has **no `.git`** (rsync excludes it) → `git diff --name-only` will NOT work in the workspace. **Decision: derive `changed_files` by parsing the patch's `+++ b/...` headers (strip `samples/tasks_service/`), NOT by git diff.** A `read-mutated-content` helper reads file bytes from the workspace after apply.
10. **THE TRAP (CONFIRMED).** `lib/conveyor/jobs/run_gate_canary.ex` *looks* like it does static-mutant discrimination — `run_case!/5` (lines 56–73) builds a `:patch_set` and passes it through `RunGate.run_gate_only!`. **But that patch_set carries only `id`/`patch_ref`/`expected_catch` (lines 61–68) — NO `changed_files`.** Every static stage that depends on `changed_files` (`ContractLock.protected_path_findings`, `PolicyCompliance.policy_file_findings`) sees an empty list and returns `[]` → PASS. Its tests pass because they inject a **stub `FixtureGateStage`** as the only stage (verified by reading the test). So `RunGateCanary` is a **looks-wired-but-vacuous** harness for static discrimination. This sub-stream does NOT extend `RunGateCanary`; it builds the real assembler inside the gauntlet. (Sub-stream E may later retire/repair `RunGateCanary`; out of scope here, but we flag it for E.)

**Derived `changed_files` (workspace-relative, parsed from `+++ b/` headers — verified by `grep '^+++ '`):**

| mutant | workspace-relative changed_files |
|---|---|
| `known_good_solution` | `tasks_service/main.py` |
| `test_weakened_or_deleted` | `.conveyor/test-packs/tasks-complete/v1/tests/test_tasks_api.py` |
| `forbidden_policy_edit` | `conveyor.plan.yml` |
| `new_codescent_high_risk` | `tasks_service/main.py` |
| `repo_prompt_injection_ignored` | `README.md` |
| `tool_output_injection_ignored` | `.conveyor/canary/tool-output.txt` |

**One more verified fact for the executor:** `samples/beads_insight` has 7 mutants, **all `test_execution` (behavioral)**; `samples/gx` has **no** `mutants.json`. So beads/gx are behavioral-only today. (Decision on whether to add static mutants there is in Slice F8.)

---

### Design posture & the central anti-vacuity contract

The whole point of this sub-stream is **anti-vacuity**: a green `false_pass_rate=0` must mean "the gate genuinely catches each planted defect for the *right reason*," not "no stage fired." The trap in §10 is exactly the failure we are inoculating against. So **every** static slice ships paired tests that prove BOTH directions:

- **BROKEN-signal case** (the mutant): the assembled context for that mutant, run through the gate, **must FAIL on the exact expected finding category** (`locked_test_pack_or_contract_changed` / `policy_file_change` / `untrusted_instruction_followed` — the 4 real-producer stages; `new_high_risk_findings`/`code_quality_delta` is ADVISORY and NOT a hard-catch category in M4, see F5). A test that only asserts `gate_passed == false` is NOT enough — we assert the **category** so a stage failing for the wrong reason (e.g. a missing-input fail-closed instead of a real catch) is caught.
- **GOOD-signal case** (known_good with the same assembler): **must PASS** every static stage. This is the fail-OPEN guard: if our assembler is over-strict (e.g. a too-broad glob, or a self-inconsistent ContractLock digest), known_good parks and we catch it immediately. **This is the "known-good reference still auto-accepts" check the ratified posture demands.**
- **DECOUPLING test** (the killer anti-vacuity assertion): a test that **removes the discriminating input** (e.g. blanks `changed_files`, or supplies an empty `policy_path_globs`) and asserts the mutant **now PASSES** — proving the catch is *driven by the real signal*, not by a fail-closed default firing on everything. This is what would have caught the `RunGateCanary` trap.

**Incremental fail-closed sequencing (ratified posture).** Each static stage is wired one slice at a time. Within a slice: (a) assemble that stage's real inputs for known_good + the one mutant, (b) add the stage to `@stages`, (c) prove known_good still PASSES the full stage set (never parks the reference), (d) prove the mutant FAILS on the right category, (e) re-confirm `false_pass_rate == 0` over the *growing* corpus, (f) green commit. We only "flip a signal fail-closed" once its real producer (the assembler input) exists. `code_quality_delta` has **no real producer in M4** and is wired **ADVISORY** (no injected fixture-oracle — F5 is cut); its mutant `new_codescent_high_risk` is `archetype:advisory` and is **NOT** in the blocking corpus.

**Why one blocking number.** Today `false_pass_rate` is scoped to the behavioral set. After this sub-stream it is scoped to the **full ENABLED NON-ADVISORY corpus** — a **manifest-derived** count (**7 today**, excluding `known_good` and any `archetype:advisory` mutant such as `new_codescent_high_risk`; **never a literal divisor**). `caught = count(enabled-non-advisory mutant not passed AND caught_by_expected_stage)`; `false_passes = enabled_total - caught`; `false_pass_rate = false_passes / enabled_total`; target `0`, blocking. One number, fed to the existing scorecard gate, no new CI wiring. The `--gate` step already fails on any blocking metric > target.

---

### New module: `Conveyor.Eval.MutantContext` (the DB-free per-mutant static-stage assembler)

**Responsibility.** Given a workspace path (post-patch), a manifest case, and the loaded plan, produce the **plain context map** the static gate stages consume — `changed_files`, `policy_path_globs`, a synthetic `contract_lock`/`agent_brief`/`test_pack`/`run_spec`, and `artifacts`/`artifact_contents` (injection content) — all DB-free, all deterministic, all self-consistent so that `known_good` passes every stage. (No `code_quality_run` — F5's fixture-oracle is cut; `code_quality_delta` is advisory.) This is the shared seam Sub-stream E reuses to wire the same static stages into the LIVE gate.

**Module:** `lib/conveyor/eval/mutant_context.ex`
**Test:** `test/conveyor/eval/mutant_context_test.exs` (`@moduletag :eval` is NOT needed — this is a pure assembler with no pytest; keep it in the default suite so `mix test --exclude eval` exercises it).

**Key function signatures (Elixir typespecs):**

```elixir
@type case_def :: map()        # a manifest entry (known_good or a mutant)
@type ws :: String.t()         # post-patch workspace path
@type ctx :: map()             # the plain gate context map

@doc """
Assemble the full static-stage context for one case. The returned map MERGES onto
the behavioral context (verification_result + test_pack_calibration) the gauntlet
already builds. DB-free; deterministic.
"""
@spec assemble(ws(), case_def(), plan :: map(), opts :: keyword()) :: ctx()
def assemble(ws, case_def, plan, opts \\ [])

@doc "Workspace-relative paths changed by the case's patch (parsed from patch +++ headers, strip prefix)."
@spec changed_files(case_def(), opts :: keyword()) :: [String.t()]
def changed_files(case_def, opts \\ [])

@doc "A self-consistent synthetic ContractLock (plain map) whose digests match the synthetic brief/test_pack/run_spec and whose protected_path_globs cover the locked test-pack."
@spec contract_bundle(ws(), plan :: map(), opts :: keyword()) ::
        %{contract_lock: map(), agent_brief: map(), test_pack: map(), run_spec: map()}
def contract_bundle(ws, plan, opts \\ [])

@doc "Read a workspace file's bytes as an injection-scan artifact-content entry, or [] if absent."
@spec artifact_content(ws(), rel_path :: String.t(), projection_path :: String.t()) :: [map()]
def artifact_content(ws, rel_path, projection_path)

# NOTE: code_quality_run/3 is CUT from M4 (see Slice F5 — code_quality_delta stays
# advisory; no fixture-oracle hard catch). A real deterministic CodeScent adapter
# is a Track-B follow-on.
```

**Called from:** `Conveyor.Eval.MutantGauntlet.run_case/4` (replacing the line-105 context construction). Also imported by Sub-stream E's live-gate wiring (shared design — see "Coordination with Sub-stream E").

**Internals the executor must implement (precise):**

- `changed_files/2`: read the case's `patch_ref` file, scan `^\+\+\+ b/(.+)$`, strip the leading `samples/<sample>/` (derive `<sample>` from `manifest["sample_repo_path"]` basename, or pass `:sample_prefix` opt = `"samples/tasks_service/"`). Drop `/dev/null`. Prefer the manifest's `changed_files` when present (known_good has it) but ALWAYS fall back to the parsed set for mutants (they lack it — verified). Dedup + sort for determinism.
- `contract_bundle/3`: build `test_pack = %{test_pack_sha256: D_tp, test_pack_ref: "tasks-complete/v1", mount_path: "/workspace/.conveyor/test-packs/tasks-complete/v1", ...}` where `D_tp = ContractEvolution.digest_value(test_pack_payload)`. Build `agent_brief` with `contract_sha256`, `acceptance_criteria`, `required_tests`, `verification_commands` lists; build `contract_lock` with `brief_sha256 = agent_brief.contract_sha256`, `acceptance_criteria_sha256 = digest_value(agent_brief.acceptance_criteria)`, `required_tests_sha256 = digest_value(agent_brief.required_tests)`, `verification_commands_sha256 = digest_value(agent_brief.verification_commands)`, `test_pack_sha256 = D_tp`, `policy_sha256 = D_policy`, and `protected_path_globs = [".conveyor/test-packs/**"]`. Build `run_spec` with `test_pack_sha256 = D_tp`, `policy_sha256 = D_policy`. **Self-consistency is the invariant**: every `check_equal` in `contract_lock.ex` must see `actual == expected` for known_good. The unit test below asserts this (the GOOD-signal guard). `mount_path` must start with `/workspace/.conveyor/test-packs/` (so `locked_mount_path?` is true) and `test_pack_mount_mode` must be `:read_only` (so `mount_findings` is empty).
- `artifact_content/3`: `if File.exists?(Path.join(ws, rel_path)), do: [%{projection_path: projection_path, content: File.read!(...)}], else: []`. Used to feed README and tool-output.txt into `RunCheck`'s `artifact_contents`.
- `code_quality_run/3`: **CUT for the M4 hard catch (see Slice F5).** `code_quality_delta` is advisory; the assembler does NOT inject a fixture-tuned blocking `code_quality_run` to manufacture a `new_codescent_high_risk` hard catch. (If E8's advisory gate consumes a real `code_quality_run` once a Track-B CodeScent adapter exists, it lands there, not as an F gauntlet fixture.)
- `assemble/4` merges: `%{changed_files: ..., patch_set: %{changed_files: ..., patch_ref: ..., id: ...}, policy_path_globs: [... + "conveyor.plan.yml", "conveyor.plan.yaml"], tool_invocations: [], artifacts: [], artifact_contents: [...], required_artifact_paths: [], contract_lock: ..., agent_brief: ..., test_pack: ..., test_pack_mount_mode: :read_only, run_spec: ...}`. (No `code_quality_run`/`code_quality_gate_blocking`/`code_quality_adapter_contract` keys — F5 is cut.) **`required_artifact_paths: []`** is critical: `RunCheck` defaults to requiring `dossier.md`+`logs/verification.json`; without overriding to `[]`, known_good would FAIL `RunCheck` with `missing_required_artifact`. (This is a known fail-OPEN→fail-CLOSED trap; the GOOD-signal test catches it.)

---

### Slice ordering (ground-up, green at each commit)

The slices build the assembler first (F1), then wire one HARD-catch static stage per slice (F2–F4; F5 is CUT — `code_quality_delta` stays advisory), then collapse the metric + rewrite the test (F6), then the reroute is folded in (it rides on F4), then validation (F7), then the optional cross-sample decision (F8). Each of F2–F4 is independently green and independently revertible.

| order | slice | adds to `@stages` (HARD catch) | closes |
|---|---|---|---|
| 1 | F1 — `MutantContext` skeleton + `changed_files` | — | (enabling) |
| 2 | F2 — wire `PolicyCompliance` (+ glob fix) | `PolicyCompliance` | `forbidden_policy_edit` discrimination |
| 3 | F3 — wire `ContractLock` (synthetic bundle) | `ContractLock` | `test_weakened_or_deleted` discrimination |
| 4 | F4 — wire `RunCheck` + injection reroute | `RunCheck` | `tool_output_injection_ignored`, `repo_prompt_injection_ignored` (rerouted) |
| 5 | F5 — **CUT**: `code_quality_delta` stays advisory; `new_codescent_high_risk` → advisory; real CodeScent adapter deferred to Track-B | — (NO hard catch) | (decision; defers a follow-on) |
| 6 | F6 — collapse to one full-corpus `false_pass_rate` over ENABLED static+behavioral mutants; rewrite `mutant_gauntlet_test.exs` | — | metric honesty |
| 7 | F7 — falsifier + abstain + scorecard `--gate` green over full corpus | — | exit gate |
| 8 | F8 — cross-sample static mutants (decision + optional impl) | — | corpus coverage |

> **The HARD-catch enabled-set is 4 static stages** (`policy_compliance`, `contract_lock`, `run_check`, `test_execution` behavioral) — `code_quality_delta` is advisory and EXCLUDED from the blocking `false_pass_rate`. The corpus count is derived from the manifest's enabled non-advisory mutants, NOT a literal (see F6).

---

### Slice F1 — `MutantContext` skeleton + `changed_files` derivation

**Goal:** stand up the DB-free assembler module with the patch-header-derived `changed_files` and a passing unit test, wired into `run_case/4` but feeding ONLY the behavioral stage (no behavior change yet — pure refactor + new capability).

**Files & functions:**
- **NEW** `lib/conveyor/eval/mutant_context.ex` — implement `changed_files/2`, `artifact_content/3`, and a stub `assemble/4` that returns the *current* behavioral context plus `changed_files`/`patch_set` (no new stages yet).
- **EDIT** `lib/conveyor/eval/mutant_gauntlet.ex:102-106` — CURRENT: builds `context = %{verification_result: ..., test_pack_calibration: @calibration}` inline. TARGET: `context = MutantContext.assemble(ws, case_def, plan, opts) |> Map.merge(%{verification_result: verification_result, test_pack_calibration: @calibration})`. `@stages` unchanged (still `[TestExecution]`). Behavior identical; `false_pass_rate` still 3-mutant-scoped.

**Discrimination test(s):** `test/conveyor/eval/mutant_context_test.exs`
- `test "changed_files parses workspace-relative paths from each static patch"` — for each of the 5 static mutants, assert `MutantContext.changed_files(case, sample_prefix: "samples/tasks_service/")` equals the exact workspace-relative path table above (e.g. `forbidden_policy_edit` → `["conveyor.plan.yml"]`). BROKEN guard: if the strip depth is wrong it returns `["samples/tasks_service/conveyor.plan.yml"]` — assert it does NOT contain the `samples/` prefix.
- `test "known_good changed_files come from the manifest when present"` — assert `["tasks_service/main.py"]`.

**Re-calibration:** none (no TrustScore weights/threshold touched in F).

**Green criteria:**
- `mix test --exclude eval --seed 0` → `mutant_context_test.exs` green (it's a pure unit test, runs in the default suite).
- `mix test --only eval --seed 0 test/conveyor/eval/mutant_gauntlet_test.exs` → still green at 3 behavioral mutants, `false_pass_rate == 0.0`, `deferred_static_stage` length still 5 (we have NOT touched the split yet — F6 does).
- `mix conveyor.eval.scorecard --gate` → still healthy.

**Dependencies:** none. First slice.
**br closed:** `br-m4-mg-001` (assembler skeleton + changed_files).
**Risks/traps:** sample-prefix derivation — hard-code via `:sample_prefix` opt defaulted from `manifest["sample_repo_path"]` to stay correct for beads/gx later. Don't use `git diff` (no `.git` in workspace — verified).

---

### Slice F2 — wire `PolicyCompliance` live (+ the plan.yml glob fix)

**Goal:** `forbidden_policy_edit` (changes `conveyor.plan.yml`) is caught by `PolicyCompliance` with category `policy_file_change`; `known_good` (changes `tasks_service/main.py`) passes `PolicyCompliance`.

**Files & functions:**
- **EDIT** `lib/conveyor/eval/mutant_context.ex` `assemble/4` — add `policy_path_globs: @default_policy_path_globs ++ ["conveyor.plan.yml", "conveyor.plan.yaml"]` and `tool_invocations: []`. (Seed-fact glob gap fix #6. We do NOT mutate `PolicyCompliance.@default_policy_path_globs` — feeding via context is non-invasive and sample-scoped.)
- **EDIT** `lib/conveyor/eval/mutant_gauntlet.ex:29` `@stages` — append `Conveyor.Gate.Stages.PolicyCompliance`. NOW two stages run for every case.

> **Sequencing wrinkle (important).** Once a static stage is added to `@stages`, EVERY case (including the 3 behavioral + known_good) runs through it. The behavioral mutants change only `tasks_service/main.py` (not a policy path), so they PASS `PolicyCompliance` — good. But `false_pass_rate` is still computed over the behavioral set in F2 (the split isn't collapsed until F6). To avoid the static mutant `forbidden_policy_edit` silently slipping in this interim, **F2's discrimination is asserted directly in the gauntlet test, not via the corpus metric yet.** F6 folds it into the metric.

**Discrimination test(s):** add to `test/conveyor/eval/mutant_gauntlet_test.exs` (or a new `mutant_gauntlet_static_test.exs`, `@moduletag :eval`):
- BROKEN-signal: `test "forbidden_policy_edit is caught by policy_compliance (policy_file_change)"` — run the single case via a new `MutantGauntlet.run_case_for(id)` test helper (or filter `report["cases"]`); assert `gate_passed == false` AND `"policy_compliance" in caught_by_stage` AND `"policy_file_change" in finding_categories`. Expected outcome: **reject**.
- GOOD-signal: `test "known_good passes policy_compliance"` — assert known_good `gate_passed == true` and `"policy_compliance"` NOT in its failed stages. Expected outcome: **accept**.
- DECOUPLING (anti-vacuity): `test "forbidden_policy_edit passes when plan.yml glob is removed"` — call `PolicyCompliance.run(%{patch_set: %{changed_files: ["conveyor.plan.yml"]}, policy_path_globs: []})` and assert `status == :passed`. Proves the catch is glob-driven, not a fail-closed default. (Directly inoculates against the §10 vacuity trap.)

**Re-calibration:** none.

**Green criteria:**
- `mix test --only eval test/conveyor/eval/mutant_gauntlet_static_test.exs --seed 0` → new tests green.
- `mix test --only eval test/conveyor/eval/mutant_gauntlet_test.exs --seed 0` → behavioral assertions still green; **known_good still passes** (now through 2 stages — the reference-still-accepts check).
- `mix conveyor.eval.scorecard --gate` → healthy.

**Dependencies:** `F1`.
**br closed:** `br-m4-mg-002` (policy_compliance live + glob fix).
**Risks/traps:** if `policy_path_globs` is too broad it could catch `tasks_service/main.py` and park known_good — the GOOD-signal test catches this. Keep the added globs to the two exact plan filenames.

---

### Slice F3 — wire `ContractLock` live (synthetic, self-consistent bundle)

**Goal:** `test_weakened_or_deleted` (edits the locked test-pack `.conveyor/test-packs/.../test_tasks_api.py`) is caught by `ContractLock` with category `locked_test_pack_or_contract_changed`; `known_good` passes `ContractLock` (all 5 sub-checks).

**Files & functions:**
- **EDIT** `lib/conveyor/eval/mutant_context.ex` — implement `contract_bundle/3` (the self-consistent synthetic ContractLock + brief + test_pack + run_spec, with `protected_path_globs: [".conveyor/test-packs/**"]`, `mount_path: "/workspace/.conveyor/test-packs/tasks-complete/v1"`); add to `assemble/4`: `contract_lock`, `agent_brief`, `test_pack`, `test_pack_mount_mode: :read_only`, `run_spec`. Pass `contract_lock_sha256` into the gate via `@gate_opts` (the `input_digests` use it but it's not a finding driver — keep the existing `"sha256:eval-gauntlet"` placeholder; the real driver is the digest *equalities* inside the bundle).
- **EDIT** `lib/conveyor/eval/mutant_gauntlet.ex:29` `@stages` — append `Conveyor.Gate.Stages.ContractLock`.

**Discrimination test(s):** `mutant_gauntlet_static_test.exs`:
- BROKEN-signal: `test "test_weakened_or_deleted is caught by contract_lock (locked_test_pack_or_contract_changed)"` — assert `gate_passed == false`, `"contract_lock" in caught_by_stage`, `"locked_test_pack_or_contract_changed" in finding_categories`. Expected: **reject**.
- GOOD-signal: `test "known_good passes contract_lock with self-consistent digests"` — assert known_good passes; AND a focused unit: `MutantContext.contract_bundle(...)` then `ContractLock.run(bundle_ctx)` returns `status: :passed` with `findings == []`. This is the **reference-accepts invariant** — proves the synthetic ContractLock is digest-self-consistent (no `*_digest_mismatch`).
- DECOUPLING: `test "test_weakened_or_deleted passes contract_lock when protected_path_globs is empty"` — set `protected_path_globs: []` (keep digests self-consistent) and assert `status: :passed`. Proves the catch is glob-driven, not a missing-input fail-close.
- BROKEN-INPUT (extra anti-vacuity): `test "contract_lock fails closed on missing bundle"` — `ContractLock.run(%{})` returns `:failed` with `missing_contract_lock`. Proves the fail-closed branch is alive (so a future regression that drops the bundle parks loudly, not silently passes).

**Re-calibration:** none.

**Green criteria:** same triad as F2 (new tests green; known_good still passes through 3 stages; scorecard healthy). `mix test --exclude eval` unaffected. `mix conveyor.eval.scorecard --gate` healthy.

**Dependencies:** `F1`, `F2` (ordering only — independent logically).
**br closed:** `br-m4-mg-003` (contract_lock live + synthetic bundle).
**Risks/traps:** the heaviest fail-open→fail-closed surface. Six digest equalities + mount checks must all hold for known_good. The GOOD-signal unit test (`findings == []`) is the load-bearing guard. **`test_pack_mount_mode` and `mount_path` are easy to forget** → `mount_findings` would park known_good with `locked_test_pack_not_read_only`/`locked_test_pack_mount_invalid`; the GOOD-signal test catches it. Use `ContractEvolution.digest_value/1` (verified at `contract_evolution.ex:159`) for `digest_value(...)` so it matches `ContractLock`'s `digest_value` (which also calls `ContractEvolution.digest_value`).

---

### Slice F4 — wire `RunCheck` live + the prompt-injection REROUTE

**Goal:** `tool_output_injection_ignored` (creates `.conveyor/canary/tool-output.txt` with "ignore previous instructions, bypass contract...") AND `repo_prompt_injection_ignored` (README "ignore the locked contract", REROUTED from `policy_compliance`) are both caught by `RunCheck` with category `untrusted_instruction_followed`; `known_good` passes `RunCheck`.

**Files & functions:**
- **EDIT** `lib/conveyor/eval/mutant_context.ex` `assemble/4` — feed `artifact_contents` built via `artifact_content/3` for the case's changed files that are scannable prose. Concretely: for `tool_output_injection_ignored`, read `.conveyor/canary/tool-output.txt`; for `repo_prompt_injection_ignored`, read `README.md`. Generalize: scan EACH `changed_file` ending in `.md`/`.txt`/`README*` into an artifact-content. Also set `required_artifact_paths: []` and `artifacts: []` so `RunCheck` doesn't fail known_good on `missing_required_artifact`/`missing_manifest` (it won't: `manifest_findings(nil, nil, _)` → `[]`, and `required_artifact_findings` with empty `required_paths` → `[]`).
- **EDIT manifest** `samples/tasks_service/.conveyor/canary/mutants.json` — `repo_prompt_injection_ignored.expected_catch.stage`: `"policy_compliance"` → `"run_check"`; `category`: `"repo_prompt_injection"` → `"untrusted_instruction_followed"`. Add `"untrusted_instruction_followed"` to its `valid_stricter_categories`. (This is the seed-fact reroute #5 — the manifest was lying about where this is catchable.)
- **EDIT** `lib/conveyor/eval/mutant_gauntlet.ex:29` `@stages` — append `Conveyor.Gate.Stages.RunCheck`.

**Discrimination test(s):** `mutant_gauntlet_static_test.exs`:
- BROKEN-signal A: `test "tool_output_injection_ignored is caught by run_check (untrusted_instruction_followed)"` — assert reject + `"run_check" in caught_by_stage` + `"untrusted_instruction_followed" in finding_categories`.
- BROKEN-signal B (the reroute): `test "repo_prompt_injection_ignored is caught by run_check after reroute"` — assert reject + `"untrusted_instruction_followed" in finding_categories` + `expected_stage == "run_check"`.
- GOOD-signal: `test "known_good passes run_check (no injection markers, no required artifacts)"` — assert known_good passes; `"run_check"` not in failed stages.
- DECOUPLING: `test "injection mutants pass run_check when artifact_contents is empty"` — assemble with `artifact_contents: []` and assert both injection mutants PASS run_check. Proves the catch is content-driven (had we forgotten to feed the README/tool-output, the gate would false-PASS — exactly the thing being tested).

**Re-calibration:** none.

**Green criteria:** triad (new tests green; known_good passes 4 stages; scorecard healthy). `mix test --exclude eval` unaffected.

**Dependencies:** `F1`. (Order after F3 by table; logically independent of F2/F3.)
**br closed:** `br-m4-mg-004` (run_check live), `br-m4-mg-005` (injection reroute + manifest fix).
**Risks/traps:** **marker exact-match.** Verified: README "ignore the locked contract" ∈ markers; tool-output "ignore previous instructions" ∈ markers (note the tool-output also says "bypass contract" but the marker is "bypassed contract" — the catch rides on "ignore previous instructions", which DOES match — do not rely on "bypass contract"). The DECOUPLING test guards the "we fed the right file" assumption. **Do NOT** feed `tasks_service/main.py` as artifact-content (it's not prose) — scope `artifact_content` to `.md`/`.txt` to avoid accidentally scanning code.

---

### Slice F5 — CUT from M4: `code_quality_delta` stays ADVISORY (no fixture-oracle hard catch); defer a real CodeScent adapter to Track-B

> **DECISION (brake-on-complexity; SOFTENS Decision 1's "wire all 14" — elevated to Open Decision 17). The fixture-tuned-regex hard catch is CUT from the M4 gauntlet.** The original F5 wired a `CodeQualityDelta` hard catch by INJECTING a deterministic `code_quality_run` whose `new_high_risk_findings` came from a TEST-AUTHORED regex (`~r/#\s*TODO.*(bypass|debug|skip)/i`) tuned to score exactly the one planted mutant. That is a reverse-engineered fixture oracle: a discrimination "catch" that passes only because the producer was written to catch precisely that one mutant and nothing else — there is no real CodeScent signal, and `code_quality_delta` is ADVISORY in the live gate (E8) anyway, so even there this catch never blocks. It spends real complexity (a synthetic adapter contract, three discrimination tests, a manifest archetype) to wire a stage with (a) no real producer and (b) no blocking role in the live gate. **Per Decision 1 "wire all 14": advisory wiring still wires it** — so `code_quality_delta` IS wired (E8, advisory, findings recorded) — we simply do NOT add a fixture-oracle HARD catch to the gauntlet.

**What F5 does in M4 (the lean version):**
- **`code_quality_delta` stays WIRED but ADVISORY** in the live gate (E8) — it runs, records `new_high_risk_findings` as a `warning`-severity finding, never blocks. This is consistent with the stage's own design (advisory unless a real deterministic CodeScent adapter contract exists, which none does in M4) and with Decision 1 (advisory wiring is wiring).
- **`new_codescent_high_risk` is marked `archetype: advisory` (and/or `enabled: false`) in `samples/tasks_service/.conveyor/canary/mutants.json`** so F's harness does NOT count it as a missed catch and the corpus count excludes it from the HARD (blocking) enabled-set. This resolves **F4** (the E8-vs-F disposition contradiction): `new_codescent_high_risk` is advisory in BOTH the live gate (E8) AND the gauntlet — no more "disabled for E but required-caught for F over the same manifest."
- **Do NOT add `Conveyor.Gate.Stages.CodeQualityDelta` to `mutant_gauntlet.ex:29` `@stages` as a HARD catch.** (It may run advisory in the live E gate; the gauntlet's blocking `false_pass_rate` is over the REQUIRED-stage catches only.)
- **A REAL deterministic CodeScent adapter is deferred to a flagged Track-B follow-on** — file the br (see the br-creation action in H7 / Section 12). When that real adapter lands, `new_codescent_high_risk` becomes a genuine hard catch and `code_quality_delta`'s required-flip is gated on the adapter contract.

**Discrimination test(s):** none new in F5 for a HARD catch (the fixture-oracle is cut). The advisory behavior is covered by E8's `advisory_stages_test.exs` (`code_quality_delta` emits a `warning` finding, gate passes; would be `blocking` only IF a real deterministic contract were present — a fixture contract proves the required-flip is one real-adapter away, NOT shipped). The anti-vacuity value of the gauntlet comes from the **4 stages with real producers** (`policy_compliance`, `contract_lock`, `run_check`, `test_execution`) — a fifth stage whose only producer is a fixture-tuned regex adds corpus breadth, not false-pass-resistance.

**Re-calibration:** none.

**Green criteria:** `mutant_gauntlet.ex` `@stages` does NOT include `CodeQualityDelta` as a hard catch; the manifest marks `new_codescent_high_risk` advisory; F6's HARD corpus count EXCLUDES it; E8's advisory test green; `mix conveyor.eval.scorecard --gate` healthy.

**Dependencies:** `F1`.
**br opened (NOT closed in M4):** a Track-B follow-on "Real deterministic CodeScent adapter for `code_quality_delta`" (filed in H7; see Section 12 NEW issues to FILE). `br-m4-mg-006`/`br-m4-mg-007` are RETIRED for M4 (the injected-run + scan-unit work is cut).
**Honesty note (DONE.md):** `code_quality_delta` is advisory-only at M4 with NO real quality oracle — `false_pass_rate == 0` must NOT be read as "the gate catches quality regressions." It catches policy/contract/injection/test regressions; quality-delta is visibility-only until the Track-B CodeScent adapter lands.

---

### Slice F6 — collapse to ONE full-corpus `false_pass_rate`; rewrite the gauntlet + test

**Goal:** the gauntlet now runs all ENABLED non-advisory mutants (3 behavioral + 4 static — `new_codescent_high_risk` is advisory, F5 cut) through `run_case/4` with the **4-stage hard-catch set** (`TestExecution`, `PolicyCompliance`, `ContractLock`, `RunCheck`); `false_pass_rate`/`mutant_catch_rate` are scoped to the **full enabled non-advisory corpus** (count derived from the manifest, 7 today); `deferred_static_stage` is empty; the legacy assertions are rewritten.

**Files & functions:**
- **EDIT** `lib/conveyor/eval/mutant_gauntlet.ex`:
  - lines 49–53: REMOVE the `split_with`; run all ENABLED NON-ADVISORY mutants through `run_case/4` against the 4-stage hard-catch set (`new_codescent_high_risk`/`code_quality_delta` is advisory — F5 cut — and is EXCLUDED from the blocking `false_pass_rate` enabled-set; it may still run advisory in the live E gate but is not a gauntlet hard catch). (Behavioral cases need pytest via `ToolchainRunner`; static cases run pytest too — that's fine and keeps `verification_result` present so `TestExecution` passes for static mutants whose defect is NOT behavioral. Verify: `test_weakened_or_deleted` weakens a test assertion → pytest still passes → `TestExecution` passes → the catch comes from `ContractLock`. Good — that's the discrimination we want.)
  - `caught` (line 55): redefine as `count(mutant where not gate_passed AND caught by its expected stage)`. Add a `caught_by_expected?/1` helper comparing `expected_catch.stage`/`category` (and `valid_stricter_categories`) against `caught_by_stage`/`finding_categories` — mirror `RunGateCanary.expected_match?/3` (lines 113–121) so a mutant rejected for the WRONG reason counts as a FALSE PASS, not a catch. This is the anti-vacuity teeth in the metric itself.
  - line 66: `deferred_static_stage` → `[]` (or drop the key; F6 test asserts it's empty/absent).
  - lines 75–82: `false_pass_rate` detail → `"#{caught}/#{total} corpus mutants caught"`; `mutant_catch_rate` detail → `"full static+behavioral discrimination set"`.
- **EDIT** `test/conveyor/eval/mutant_gauntlet_test.exs`:
  - line 22: `real_exec_mutants == 3` → **a count DERIVED FROM THE MANIFEST, not a literal.** The blocking corpus is the manifest's ENABLED, NON-advisory mutants (excluding `known_good` and excluding any `archetype: advisory`/`enabled: false`). tasks_service `mutants.json` has 1 `known_good` + 8 mutant ids. Of the 8: `new_codescent_high_risk` is now `archetype: advisory` (F5 cut), so the HARD enabled-set is **7** = `patch_unknown_id_returns_200`, `completed_not_persisted_to_list`, `default_completed_missing` (3 behavioral) + `test_weakened_or_deleted`, `forbidden_policy_edit`, `repo_prompt_injection_ignored` (rerouted to run_check), `tool_output_injection_ignored` (4 static). **Compute the expected count from the manifest** (`length(enabled_non_advisory_mutants)`), assert `known_good` is excluded explicitly, and assert `caught == that count`, `false_pass_rate == 0.0`, `mutant_catch_rate == 1.0`. Do NOT hard-code `7` or `8` — derive it, so adding/disabling/advisory-marking a mutant does not silently break or vacuously pass the test. (The count is 7 today = 9 ids minus `known_good` minus `new_codescent_high_risk`-advisory — derived, not literal.)
  - lines 27–30: the per-mutant loop — replace `assert "test_execution" in c["caught_by_stage"]` with `assert caught_by_expected_stage(c)` (each ENABLED non-advisory mutant caught by ITS expected stage). Keep `refute c["gate_passed"]`. Advisory mutants (`new_codescent_high_risk`) are NOT in this loop.
  - lines 33–37: DELETE the "deferred to B2" test; REPLACE with `test "no static stage is deferred — all enabled hard-catch stages run live"` asserting `report["deferred_static_stage"] in [[], nil]` (the advisory `code_quality_delta` is simply not a hard-catch stage, not "deferred").
  - The beads test (lines 50–74): leave at 7 behavioral (beads is behavioral-only — verified). Update only if F8 adds beads static mutants.

**Discrimination test(s):** the rewritten `mutant_gauntlet_test.exs` IS the corpus-level discrimination (all ENABLED non-advisory static+behavioral mutants caught by their expected stage, `false_pass_rate == 0`, count derived from the manifest). The per-stage BROKEN/GOOD/DECOUPLING tests from F2–F4 remain and are the granular anti-vacuity proofs.

**Re-calibration:** none.

**Green criteria:**
- `mix test --only eval --seed 0 test/conveyor/eval/mutant_gauntlet_test.exs test/conveyor/eval/mutant_gauntlet_static_test.exs` → all green: `false_pass_rate == 0.0`, `mutant_catch_rate == 1.0`, `real_exec_mutants == <manifest-derived enabled-non-advisory count>` (7 today), `deferred_static_stage` empty.
- `mix conveyor.eval.rung0` then `mix conveyor.eval.scorecard --gate` → exit 0 (healthy); the emitted `false_pass_rate` now reflects the full ENABLED non-advisory corpus.
- `mix test --exclude eval --seed 0` → green (unit assembler).

**Dependencies:** `F1`, `F2`, `F3`, `F4` (all HARD-catch stages must be live + assembler complete before collapsing the metric; F5 is a cut/decision, no hard catch).
**br closed:** `br-m4-mg-008` (full-corpus false_pass_rate), `br-m4-mg-009` (mutant_gauntlet_test rewrite).
**Risks/traps:** **the biggest false-confidence risk in the whole sub-stream.** If `caught` were defined as merely `not gate_passed`, a static mutant rejected for the wrong reason (e.g. a stage fail-closing on a missing input) would count as a catch and `false_pass_rate` would read 0 while the gate is actually broken. The `caught_by_expected?` helper is mandatory — it is what makes "0" mean "caught for the right reason." Add a test that *injects a wrong-reason rejection* (e.g. a mutant whose only finding is `gate_stage_exception`) and asserts it counts as a false PASS, not a catch.

---

### Slice F7 — abstain proof + external-buggy falsifier + scorecard `--gate` over full corpus

**Goal:** prove the activated gate (a) ABSTAINS deterministically when a genuinely-unassessable signal is absent (not false-pass), and (b) actually CATCHES a real, externally-planted defect — the falsifier probe. Confirm the HARD exit gate: zero false-pass on the full corpus in CI.

**Files & functions:**
- **EDIT** `lib/conveyor/eval/mutant_context.ex` — add a documented `:abstain_when_unassessable` path for the one genuinely-not-assessable signal in THIS sub-stream: **hermeticity**. Per ratified decision #3, hermetic backend = `docker --network=none` only; when `ToolchainRunner.docker_available?() == false`, the gauntlet runs `:local`, which CANNOT block the network. `ToolchainRunner.integrity_observations` already OMITS hermeticity under `:local` (verified, `toolchain_runner.ex:228-235`) → it stays `not_assessed`/non-blocking. **F7's job is to assert this is honest, not laundered:** a test that runs the gauntlet under `:local` and asserts NO case is rejected *for hermeticity* and NO case false-PASSES *because* hermeticity was claimed. (Hermeticity is NOT one of the 5 static-mutant stages — it's an IntegritySentinel signal — so this is a guardrail test, not a stage wiring. It documents the `not_assessed` vs `fail-closed` taxonomy boundary the ratified posture demands.)
- **NEW falsifier fixture** `samples/tasks_service/.conveyor/canary/mutants/external_buggy_commit.patch` + a manifest entry `external_buggy_commit` tagged `enabled: false` by default (so it does NOT inflate the corpus count) — a real behavioral defect distinct from the existing mutants (e.g. off-by-one in list ordering). **NEW test** `test "falsifier: external_buggy_commit is caught (gate is not vacuously green)"` (`@moduletag :eval`) that enables just that mutant and asserts it is rejected by `test_execution`. This is a gauntlet-local sanity falsifier. **NOTE (coordinate with H5):** the AUTHORITATIVE M4 hard falsifier is the dedicated `falsifier/` set of 4 FIXED targets owned by H5 (`Conveyor.Eval.FalsifierProbe`), DISTINCT from the F gauntlet corpus so the check is INDEPENDENT, not circular (re-running F's own tuned-against patches would prove nothing new). F7's `external_buggy_commit` is a small extra sanity defect inside the gauntlet, not the ratified-exit hard falsifier — that is H5. Keep them distinct.

**Discrimination test(s):**
- `test "abstain: under :local backend, hermeticity is not_assessed and never causes a false PASS"` — run the full corpus with `backend: :local`; assert `false_pass_rate == 0.0` AND no case's findings claim `hermeticity: blocked`. ($0, deterministic.)
- `test "falsifier: external_buggy_commit (enabled) is caught"` — as above. Proves the gate is not vacuously green on a fresh, never-before-seen defect.

**Re-calibration:** none.

**Green criteria:**
- Full eval run: `mix conveyor.eval.rung0 && mix conveyor.eval.scorecard --gate` → exit 0; `false_pass_rate == 0` over the enabled non-advisory corpus (manifest-derived count, 7 today).
- All discrimination + falsifier + abstain tests green: `mix test --only eval --seed 0`.
- The HARD blocking exit (ratified #5): `mix conveyor.eval.scorecard --gate` green in CI on the FULL corpus + every discrimination test green + abstain proven ($0, deterministic). (The live-Codex pass + external catch-rate measurement are MEASURED/reported by the broader M4, not gated here — this sub-stream provides the static-corpus half of the falsifier probe.)

**Dependencies:** `F6`.
**br closed:** `br-m4-mg-010` (abstain/not_assessed honesty), `br-m4-mg-011` (external-buggy falsifier probe).
**Risks/traps:** keep the falsifier `enabled: false` so it doesn't change the asserted corpus count (manifest-derived, 7 today) in F6's test; the falsifier test flips it on locally. Don't conflate hermeticity (IntegritySentinel, not_assessed under :local) with the 4 hard-catch static stages — the taxonomy boundary is the point.

---

### Slice F8 — cross-sample static mutants (DECISION + optional impl)

**Goal:** decide whether to add static mutants to `beads_insight`/`gx` (today behavioral-only / nonexistent), and if so, implement them off the same assembler.

**Decision (my recommendation, overridable by Robert):** **For M4, extend ONLY `tasks_service` to the static corpus; keep `beads_insight` behavioral-only (7 mutants, all `test_execution` — verified) and do NOT add a `gx` canary.** Rationale (pragmatism brake): the static stages are sample-agnostic (the assembler is parameterized by `sample_prefix`/plan), so one fully-discriminated sample *proves the harness*. Replicating 5 static patches × 2 more samples is corpus-breadth, not new capability — high effort, low marginal signal for the M4 exit. The `false_pass_rate` blocking number is already non-vacuous with tasks_service alone. **Flag as a fast-follow:** once Sub-stream E wires the live gate, add one static mutant per category to beads to prove cross-sample generality (a `br` follow-on, not M4-blocking).

**If Robert wants it in M4 (optional impl):** add to `samples/beads_insight/.conveyor/canary/mutants.json` one static mutant per HARD-catch stage (policy edit to `pyproject.toml`/a beads policy file → `policy_compliance`, a weakened locked test in the beads test-pack → `contract_lock`, a README injection → `run_check`), with patches under `samples/beads_insight/.conveyor/canary/mutants/`. (No `code_quality_delta` mutant — advisory, F5 cut.) The assembler needs NO change (it's `sample_prefix`-parameterized); only `MutantContext.contract_bundle` must resolve the beads test-pack path/digest (drive it from `manifest`/plan, not a tasks_service constant). Update the beads test (`mutant_gauntlet_test.exs:50-74`) corpus count accordingly (derived from the manifest).

**Discrimination test(s):** if implemented, mirror F2–F5's BROKEN/GOOD/DECOUPLING triad per beads static mutant.

**Re-calibration:** none.

**Green criteria:** if implemented, `mix test --only eval --seed 0` green over both samples; `mix conveyor.eval.scorecard --gate` healthy. If not implemented (recommended), this slice is a documented decision only — no code.

**Dependencies:** `F6` (assembler must be sample-parameterized).
**br closed:** `br-m4-mg-012` (cross-sample decision; impl only if elected).
**Risks/traps:** if implemented, the beads `contract_bundle` must not hard-code tasks_service paths — the seed bug to avoid is a tasks-specific test-pack glob leaking into the beads context (would park beads known_good). Parameterize from the manifest/plan.

---

### Coordination with Sub-stream E (live-gate wiring) — SHARED DESIGN

Sub-stream E wires these SAME static stages into the LIVE production gate. The shared seam is **`Conveyor.Eval.MutantContext` and the context shape it produces** — E should consume the *same keys* (`changed_files`, `policy_path_globs`, `contract_lock`/`agent_brief`/`test_pack`/`run_spec` bundle, `artifact_contents`). (No `code_quality_run` — advisory in both, F5 cut.) The crucial DIFFERENCE E must honor:

- **F (this sub-stream) is DB-FREE by invariant** — synthetic plain-map ContractLock. **E is DB-backed** — it assembles the real `ContractLock`/`AgentBrief`/`RunSpec` records via `GateContext.assemble` (DB). For `code_quality_delta`, E runs it ADVISORY (E8) with no real adapter at M4; a real `code_quality_run` from a Track-B CodeScent adapter is a follow-on. E must NOT import F's synthetic bundle into production; F must NOT import `GateContext.assemble`. The SHARED artifact is the **context-key contract** (which keys each static stage reads), not the producers.
- **The policy-glob fix** (plan.yml) and the **injection reroute** (`repo_prompt_injection_ignored` → run_check) are corpus/manifest truths that E inherits — E reads the same manifest, so the reroute and the manifest edits in F4 are visible to E automatically.
- **Hand-off note for E:** the `caught_by_expected?` discrimination helper (F6) and the `policy_blocked`/`critical-stop` Finalizer branches (E's job) should agree on finding categories. Share the category vocabulary: `policy_file_change`, `locked_test_pack_or_contract_changed`, `untrusted_instruction_followed`, `new_high_risk_findings`.

---

### Trust-score note (why this sub-stream has NO re-calibration steps)

The ratified plan asks each slice to state TrustScore weight/threshold deltas. **This sub-stream touches none.** MutantGauntlet's blocking signal is `false_pass_rate` (target 0), a deterministic discrimination metric — not a TrustScore-weighted signal. The trust_evidence.ex fail-open→fail-closed flips (replay_divergence, provenance_attestation, canary_freshness, etc.) live in the producer Sub-streams (the trust-producer + abstain streams), which re-tune weights/threshold against the `samples/beads_insight + samples/gx` known-good reference. **F's contribution to that reference is the canary_freshness producer half** noted in ratified decision #4: F7's `gate-canary`/MutantGauntlet health record is the source for `canary_freshness`. The actual weight/threshold re-tune for `canary_freshness` happens in the trust-producer Sub-stream, against the known-good reference; F just guarantees the health-record producer exists and is honest. **No weight/threshold number changes here; the known-good reference (beads_insight + gx) is never parked by anything in F** (F only adds blocking discrimination to the tasks_service canary corpus, which is separate from the beads/gx auto-accept reference).

---

### CI wiring (unchanged — by design)

No new CI step. The existing chain holds: `mix conveyor.eval.rung0` → `MutantGauntlet.emit!()` (now emitting full-corpus `false_pass_rate`) → `eval/scorecards/inputs/mutant_gauntlet.json` → `mix conveyor.eval.scorecard --gate` (the "Eval scorecard gate" step in `ci.yml`) → exit non-zero on any blocking metric. Verified the gate-step semantics in `Mix.Tasks.Conveyor.Eval.Scorecard.exit_code/2` + `Scorecard.healthy?/1`. **The only thing that changes in CI is that the existing blocking number now discriminates 5 more defect classes.**

---

### Consolidated br issues this sub-stream closes

`br-m4-mg-001` (MutantContext skeleton + changed_files), `br-m4-mg-002` (policy_compliance live + plan.yml glob fix), `br-m4-mg-003` (contract_lock live + synthetic bundle), `br-m4-mg-004` (run_check live), `br-m4-mg-005` (injection reroute + manifest fix), `br-m4-mg-008` (full-corpus false_pass_rate over enabled non-advisory mutants), `br-m4-mg-009` (mutant_gauntlet_test rewrite), `br-m4-mg-010` (abstain/not_assessed honesty), `br-m4-mg-011` (external-buggy falsifier probe), `br-m4-mg-012` (cross-sample decision). **`br-m4-mg-006`/`br-m4-mg-007` are RETIRED for M4** (the F5 injected-run + scan-unit work is cut); the real CodeScent adapter is a separate Track-B follow-on (filed in H7).

> These `br-m4-mg-*` ids are placeholders I am proposing — the actual M4 br backlog ids should be confirmed/created by Robert (the seed facts reference `dr1m.*` integrity-fix ids owned by other sub-streams; F does not own those). If real br ids already exist for MutantGauntlet static extension, map these slices onto them.

---

### Full risk/trap register (carried forward + new)

1. **The §10 vacuity trap (carried):** `RunGateCanary` looks like static discrimination but its patch_set has no `changed_files` and its tests use a stub stage. We do NOT extend it; the DECOUPLING tests in F2–F5 are the antidote. Flag for Sub-stream E: `RunGateCanary` should be repaired or retired so it doesn't become a second false-confidence harness.
2. **Metric vacuity (F6):** `caught` must require catch-by-EXPECTED-stage, not merely `not gate_passed`. A wrong-reason rejection counting as a catch would make `false_pass_rate=0` a lie. Mandatory `caught_by_expected?` + the wrong-reason test.
3. **ContractLock self-consistency (F3):** six digest equalities + mount checks must hold for known_good or the reference parks. GOOD-signal unit (`findings == []`) is load-bearing.
4. **code_quality_delta fixture-oracle CUT (F5):** the manufactured producer is removed — it was a fixture-tuned regex catching exactly one mutant (reverse-engineered to the fixture), for a stage advisory in the live gate. `code_quality_delta` stays advisory (no hard catch in the gauntlet); `new_codescent_high_risk` is advisory in both; a genuine CodeScent adapter is a Track-B follow-on. This removes the single clearest over-build.
5. **RunCheck required-artifacts default (F4):** without `required_artifact_paths: []`, known_good fails `RunCheck` on `missing_required_artifact`. GOOD-signal test catches it.
6. **Policy glob over-breadth (F2):** too-broad globs park known_good. Keep to the two exact plan filenames.
7. **Reroute exactness (F4):** the reroute relies on the README marker "ignore the locked contract" being in `@injection_markers` (verified). If RunCheck's marker list ever changes, the DECOUPLING/BROKEN tests fail loudly.
8. **Workspace has no `.git` (F1):** `git diff` unavailable — derive `changed_files` from patch headers. Verified.
9. **Pytest runs for static mutants too (F6):** static mutants still execute pytest (so `TestExecution` has a `verification_result`); their defect is non-behavioral so pytest passes and the catch comes from the static stage. Confirm `test_weakened_or_deleted`'s weakened assertion still leaves pytest green (it loosens `== 404` to `in [200, 404]` — the original 404 still passes). Verified.
10. **Cross-sample leakage (F8, if elected):** beads `contract_bundle` must not inherit tasks_service paths/digests. Parameterize from manifest/plan.
11. **Incremental fail-closed ordering:** each of F2–F4 adds exactly one HARD-catch stage and proves known_good still passes the GROWING stage set before the next slice (F5 is a cut/decision, no stage added). Never collapse the metric (F6) until the 4 hard-catch stages + assembler are green. This is the ratified "never park the known-good reference; stay green at every commit" posture, enforced slice by slice.

---

## C — IntegritySentinel dormant probe producers (key: `C-integrity-probes`)

> **One-paragraph orientation for a zero-context executor.** Conveyor has a *real, deterministic* anti-vacuity oracle — `Conveyor.Verification.IntegritySentinel` — that evaluates 10 probes over a map of "observations" and folds them into a verdict (`trustworthy | suspect | not_assessed | untrustworthy`). The oracle is fully wired into the gate's trust score: `verify.ex` → `output["integrity_verdict"]` → `TrustEvidence` → `TrustScore`, and `TrustScore` **hard-requires** `integrity_verdict == "trustworthy"` for auto-accept (`lib/conveyor/gate/trust_score.ex:106`). The problem M4 fixes here is the **producer side is nearly empty**: only 2 of 10 probes (`source_mutation`, `hermeticity`) ever receive an observation, and `verify.ex:10` only admits those 2 to `required_probes`. So on the default `:local` backend the verdict is honestly `not_assessed` (asserted at `test/conveyor/first_light_production_loop_test.exs:87`). This sub-stream **builds a real observation producer for each dormant probe** and incrementally admits the cheap, high-confidence ones to `required_probes` — flipping each from fail-open to fail-closed only *after* its real producer exists and the known-good reference still auto-accepts. The blueprint for the exact observation shapes already exists in `lib/conveyor/eval/sentinel_fixtures.ex:24-60` (`clean_observations/0`) and `test/conveyor/test_integrity_sentinel_test.exs:74-110`; we replicate those shapes from real loop data instead of fixtures.

---

### VERIFICATION OF SEED FACTS (done before designing — all confirmed, with material nuances)

I read every named module at the named lines. The seed facts are accurate. Material additions a zero-context executor MUST know:

1. **`verify.ex` does NOT call the sentinel directly — it calls `IntegrityEvidence.verdict/2`** (`lib/conveyor/stations/verify.ex:27-30`), passing `required_probes: @integrity_probes` where `@integrity_probes = ["hermeticity", "source_mutation"]` (STRING list, `verify.ex:10`). `IntegrityEvidence.verdict/2` (`lib/conveyor/gate/integrity_evidence.ex:39-56`) is a thin wrapper that supplies a default spec + `evaluated_at` and calls `IntegritySentinel.run/3`, returning `run["verdict"]`. **Our `required_probes` edits land in `verify.ex:10`, not in the sentinel's `@default_probes`** (which stays the full 10 for the unit/tournament tests). This is the single switch that turns a probe from dormant→live in the loop.

2. **`not_assessed` is currently laundered to `"trustworthy"` by `TrustEvidence.integrity/1`** (`lib/conveyor/gate/trust_evidence.ex:54-56`): `integrity(_verdict)` returns `"trustworthy"` for *anything* that is not `:suspect`/`:untrustworthy`, including `not_assessed`. So **today** a `:local` run's integrity component already scores `1.0` and passes `trustworthy?/1` — the gate is fail-OPEN on integrity. **Sub-stream D owns un-laundering this — `D4` ONLY, co-shipped atomically with `C1` (the first probe admission) in M4.8 — NOT Sub-stream A** (A un-launders only calibration + baseline; B never touches integrity). My slices are sequenced so that *the first probe we admit to `required_probes` (`C1`) is the moment integrity stops being `not_assessed` on the reference and becomes a real `trustworthy`* — which is exactly the atomic `D4+C1` commit, so the un-laundering and the first admission land together (the reference goes 0.925→0.925, never committing the 0.775 park state). **This is the central cross-stream dependency; see the canonical ownership statement (§6/§7) and "Re-tuning coordination with D4" below.**

3. **The hermeticity vocabulary is split across two functions in `toolchain_runner.ex`** and only ONE feeds the sentinel. `hermeticity/1` (`:116-126`) returns a 4-key STRING map (`network/clock/rng/locale` with values like `"tz_pinned"`) — this is **NOT** what the sentinel reads and is *not* merged into observations. The function that actually feeds observations is `hermeticity_observation/1` (`:241-250`), a 6-key ATOM map (`network/clock/rng/ordering/locale/shared_state` with atom values `:blocked/:controlled/:seeded/:stable/:pinned/:isolated`) — matching `@hermetic_controls` (`integrity_sentinel.ex:23-30`) exactly. It is merged into `integrity_observations/2` (`:228-235`) **only under `:docker`** (`:232`). Hermeticity is therefore **not in scope for this sub-stream's "flip fail-closed" work** (it is docker-only and already honest); we leave it as the architectural model for "genuinely not assessable on this backend → omit observation → `not_assessed`/non-blocking." Sub-stream D owns the docker-availability *abstain* refinement.

4. **`integrity_observations/2` (`toolchain_runner.ex:228-235`) is the single merge point** the seed facts call "toolchain_runner.ex:108." Confirmed: `verification_result/3` does `Map.put("integrity_observations", integrity_observations(opts, mutated))` at `:108`. The `result_digest` is computed at `:107` **before** the integrity key is attached (`:103-105` comment), so adding probe observations **cannot** perturb the replay/result digest. This is a load-bearing invariant — **every new producer must merge into `integrity_observations`, never into the digested `result`.** (Sub-stream B's replay work relies on this same property.)

5. **Where producers get their raw data — confirmed sources:**
   - `source_mutation` (LIVE): snapshot diff of `src/` around the pytest run (`toolchain_runner.ex:147-149, 254-273`). Backend-agnostic. Already correct.
   - `mount_boundary` needs `write_violations` (`integrity_sentinel.ex:136-141`): same snapshot machinery, but widened to detect writes **outside** the writable roots (the workspace). Data near `Gate.Stages.WorkspaceIntegrity` (`lib/conveyor/gate/stages/workspace_integrity.ex`) which already reasons about `touches_locked_paths`/`base_commit`.
   - `mapping` needs `obligation_refs` with `obligation_id` + `acceptance_ref` + `interface_oracle_ref` (`integrity_sentinel.ex:126-134, 197-200`): the plan's `acceptance_criteria` (`samples/beads_insight/conveyor.plan.yml:82-161`, keyed `AC-001..` with `required_test_refs`) + the contract's obligation/oracle identity. Confirmed plan shape: each AC has `key`, `text`, `requirement_refs`, `required_test_refs`.
   - `required_artifacts` needs `required` + `present` (`integrity_sentinel.ex:143-153`): `record_evidence` station's recorded artifact set (`lib/conveyor/stations/record_evidence.ex`) vs the contract's required artifacts; `Gate.Stages.RunCheck` already has a `@required_artifact_paths ["dossier.md", "logs/verification.json"]` (`run_check.ex:22`) precedent.
   - `falsifier_survival` / `falsifier_preservation` (`integrity_sentinel.ex:83-97, 182-192`): `lib/conveyor/test_architect/falsifier_preservation.ex` + `Conveyor.Verification.evaluate_falsifier_preservation/2`.
   - `base_calibration` (`integrity_sentinel.ex:70-81`): `baseline_health` + `acceptance_calibration` stations (**sub-stream A**).
   - `repeatability` (`integrity_sentinel.ex:110-124`): a rerun + `result_digest` (**sub-stream B**).
   - `hidden_dependency` (`integrity_sentinel.ex:162-180`): network/secret access — docker/sandbox-only (**sub-stream D**).

6. **The static falsifier corpus already exists: E8 SentinelTournament** (`lib/conveyor/eval/sentinel_tournament.ex`) drives `SentinelFixtures.trip_cases/0` (one planted vacuity per `rule_key`) and emits `sentinel_evasion_rate` (blocking, target 0) + `sentinel_probe_coverage` (target 1) to the scorecard. This is the **static-stage discrimination corpus** my slices must keep at 0 evasions. Every probe I admit is already covered by a trip case in `sentinel_fixtures.ex:68-172`. **I do not need to add trip cases for the 10 existing probes; I DO need to ensure my real producers emit the same field names the trip cases perturb, so a real broken signal trips the same `rule_key`.**

7. **`br` issues confirmed.** The parent feature is `software-factory-ai-dr1m.1` (ADR-23 ternary gate / TrustScore). Its comment log explicitly defers exactly this work: *"DEFERRED (own pass, not faked): observation production in the loop (hermeticity from sandbox/toolchain env, source-mutation/mount-boundary from diff, falsifier survival from contract seeds)…"* This sub-stream is that deferred pass. There is **no pre-existing granular `br` issue per probe** — I specify the `br` issues to CREATE in the "br issues" section (do not invent IDs; create them).

---

### TAXONOMY (ratified) — applied per probe

| Bucket | Meaning | Probe behavior | Examples in this sub-stream |
|---|---|---|---|
| **measured & good** | producer ran, signal clean | observation present, probe `passed` | clean reference slice on every admitted probe |
| **measured & bad** | producer ran, signal dirty | observation present, probe `failed`/`suspect` → verdict `untrustworthy`/`suspect` → **abstain (park)** | mount-boundary write violation; missing required artifact; unmapped obligation; dropped falsifier seed |
| **should-be-measured but producer missing** | we *expected* a signal and didn't get one | **fail-closed**: admit to `required_probes`; absent observation → `not_assessed` → (post-A) non-1.0 → does NOT clear `trustworthy?` if A maps `not_assessed` to blocking… **see nuance** | a probe we promised to produce but the producer crashed/returned `nil` |
| **genuinely not assessable on this backend** | backend can't observe it | **NOT** in `required_probes`; omit observation → `not_assessed` → non-blocking | hermeticity on `:local` (docker-only); hidden_dependency on `:local` (sub-stream D) |

**Critical nuance on "fail-closed" mechanics (read twice).** `IntegritySentinel.verdict` folds `not_assessed` to an overall `not_assessed` verdict (`integrity_sentinel.ex:211`) only when *no* probe failed/suspect. `TrustScore.trustworthy?/1` requires `integrity_verdict == "trustworthy"` (`trust_score.ex:106`). So **once we admit a probe to `required_probes`, a clean reference must produce `passed` for it — otherwise the reference verdict becomes `not_assessed` and (post-A un-laundering) the reference would PARK.** This is the fail-closed trap the ratified posture warns about. Therefore the slice ordering is strict: **for each probe, the real producer for the CLEAN reference must yield `passed` BEFORE we admit the probe.** We never admit a probe whose clean-reference producer is missing or returns `nil`. "Fail-closed for a missing producer" applies to *future* slices that promise but don't deliver — it is enforced by the discrimination test (a slice that admits a probe without a working clean producer will park the reference and the green gate will catch it).

---

### SLICE ORDERING & DEPENDENCIES (within this sub-stream and across)

Admit probes cheapest-and-most-independent first. **The M4 admission rule (anti-decorative brake — F23): a probe is admitted to `required_probes` ONLY if the known-good reference produces a NON-empty, genuinely-evaluated instance of it (a real measured-good observation), so its fail-closed claim is not vacuous on the reference.** Applying that rule:

- **ADMITTED to `required_probes` in M4** (the reference exercises a real instance): `source_mutation` (already live; C0 hardens), `mount_boundary` (C1; real locked-path set on the reference), `mapping` (C2; ONLY IF the beads ACs genuinely exercise the `(obligation_id, acceptance_ref, interface_oracle_ref)` oracle triple — verified in C2; all 16 beads ACs have `required_test_refs`, so they do).
- **NOT admitted to `required_probes` in M4 — kept as the EXISTING static `SentinelTournament` coverage (already green), with live admission flagged as a follow-on:** `required_artifacts` (C3) and `falsifier_preservation`/`falsifier_survival` (C4). On the reference these are DECORATIVE — `required_artifacts` with `required==[]` is a no-op pass; `falsifier_*` with no seeds is trivially `passed`. Admitting them to `required_probes` would be fail-OPEN-in-disguise (the probe can never fail for the reference because the reference never exercises it). So C3/C4 BUILD the producers and prove them via the static E8 `SentinelTournament` trip cases + producer-driven BROKEN-half tests, but do NOT flip them into the live `required_probes` set until the loop supplies a real required-artifact set and a real falsifier seed for the reference (a flagged follow-on — see C3/C4). **This removes ~2 slices of live-admission complexity whose reference half is decorative, while keeping the discrimination coverage (the static trip cases are already green).**

**Where a probe IS admitted (mount_boundary, mapping), the BROKEN-half MUST drive the REAL producer** (e.g. an actual locked-path write during a real verify run, as C1's `:eval` variant does) — NOT a hand-built observation map fed straight to `IntegritySentinel.verdict`. Replace every "feed `IntegritySentinel.verdict` a synthetic map" broken-half with a producer-driven one, OR label it explicitly as a unit-level (not end-to-end) check distinct from the admitted live probe.

**Deferred out of this sub-stream:** `base_calibration` (→ A), `repeatability` (→ B), `hidden_dependency` (→ D), `hermeticity` (already docker-honest; D owns abstain). Each admitted probe is one slice ending in a green commit.

```
C0  source_mutation discrimination hardening      (no new producer; closes a vacuity gap)   depends: —
C1  mount_boundary producer + ADMIT to required_probes + backend-dependent required_probes   depends: E (WorkspaceIntegrity data) [soft], D4 (un-laundering) [HARD — co-ships ATOMIC with C1 in M4.8]
C2  mapping producer + ADMIT (reference exercises a real oracle triple)   depends: E (AcceptanceMapping data) [soft]
C3  required_artifacts producer — BUILT + proven via static trip cases; NOT admitted to required_probes in M4 (decorative on reference); live-admission flagged follow-on   depends: —
C4  falsifier_preservation + falsifier_survival — BUILT + proven via static trip cases; NOT admitted to required_probes in M4 (no reference seeds); live-admission flagged follow-on   depends: TestArchitect seeds [soft]
C5  consolidated re-tune + reference auto-accept proof + falsifier probe  depends: A, B, D for final threshold; closes the sub-stream
```

**The HARD cross-stream gate (the atomic co-ship — see Section 7's re-cut M4.8):** C1 (first admission) and **D4** (the un-laundering of `not_assessed` in `TrustEvidence.integrity/1` — owned by **D**, NOT A) MUST land in the **SAME atomic commit** (M4.8). Reason: until D4 lands, `not_assessed` scores 1.0 and passes `trustworthy?`, so admitting a probe changes *nothing observable* and the discrimination test for "broken signal → park" is **vacuous** (the reference auto-accepts regardless because `not_assessed` is laundered). And D4 alone (without C1's clean probe) drops the reference to 0.775 → park. Co-shipped: D4 un-launders AND C1's clean `mount_boundary` + `source_mutation` yield a genuine `trustworthy` → reference stays at 0.925, never committing 0.775. **A (the calibration/baseline/replay un-laundering) is a separate, earlier concern — A does NOT own the integrity flip.** This is the anti-vacuity heart of the whole sub-stream. See per-slice "Anti-vacuity guard" and the M4.8 PRECONDITION GUARD (`band_of_output(%{}) == :abstain` before admitting).

---

### NEW SHARED MODULE (created in C1, extended through C4)

**`Conveyor.Verification.IntegrityProbes`** — `lib/conveyor/verification/integrity_probes.ex`

Responsibility: the single place that turns real loop data into the `IntegritySentinel` observation map. Pure (no I/O, no Ash, no clock) — it takes already-collected facts and returns observation sub-maps. Called from `Conveyor.Stations.Verify.run/2` (and from `ToolchainRunner` for the `source_mutation`/`mount_boundary` snapshot-derived pieces, which need filesystem access — those stay in the runner and are *merged* with this module's output). This split keeps filesystem observation in the runner (where the snapshot lives) and contract/evidence-derived observation pure and unit-testable.

Key signatures (Elixir typespecs):

```elixir
defmodule Conveyor.Verification.IntegrityProbes do
  @type observation :: %{optional(String.t()) => term()}
  @type observations :: %{optional(String.t()) => observation()}

  # C2: build the mapping observation from the contract's acceptance criteria +
  # the obligation/oracle identity carried in the run_spec / agent_brief.
  @spec mapping(acceptance_criteria :: [map()], obligations :: [map()]) :: observation()

  # C3: required vs present artifacts. `required` from the contract's declared
  # required-artifact set; `present` from the recorded evidence projection paths.
  @spec required_artifacts(required :: [String.t()], present :: [String.t()]) :: observation()

  # C4: falsifier preservation/survival from the Test Architect preservation report.
  @spec falsifier_preservation(report :: map()) :: observation()
  @spec falsifier_survival(report :: map()) :: observation()

  # Convenience: merge all contract/evidence-derived observations the verify
  # station can supply on this backend, given the assembled inputs.
  @spec from_verify_inputs(map()) :: observations()
end
```

`mount_boundary` and `source_mutation` are produced in `ToolchainRunner` (filesystem snapshot) — `IntegrityProbes` does **not** own them; it owns the contract/evidence-derived probes. `Stations.Verify` merges `verification_result["integrity_observations"]` (runner-produced: `source_mutation`, `mount_boundary`, docker-only `hermeticity`) with `IntegrityProbes.from_verify_inputs/1` (contract-derived: `mapping`, `required_artifacts`, `falsifier_*`) before calling `IntegrityEvidence.verdict/2`.

---

### RE-TUNING COORDINATION WITH D4 (the shared hazard — read before any slice)

> **OWNERSHIP CORRECTION (canonical):** the un-laundering of `not_assessed` in `TrustEvidence.integrity/1` is owned by **D4**, co-shipped ATOMICALLY with C1 (and D3). Sub-stream **A** un-launders ONLY calibration + baseline and never touches the integrity clause. Earlier drafts of this section said "A un-launders integrity" / "co-ship with A" — that is WRONG and superseded. Read every "A" in the paragraphs below that refers to the integrity flip as **D4**.

**Current numbers (verified `trust_score.ex:58-65, 78`):**
```
weights:    integrity 0.30, calibration 0.20, baseline 0.20, replay 0.15, corpus 0.15   (Σ=1.0)
threshold:  auto_accept 0.9
component scores: integrity_score "trustworthy"=1.0, "not_assessed"=0.5, "suspect"=0.5, else 0.0
```

**The distribution shift this sub-stream causes.** Today on the reference (`:local`): integrity verdict is `not_assessed`. But `TrustEvidence.integrity/1` launders it to `"trustworthy"` → integrity_score = **1.0**. So the reference score today is `0.30·1.0 + 0.20·cal + 0.20·base + 0.15·replay + 0.15·corpus`. With calibration `:valid` (1.0), baseline `:green` (1.0), replay `:none` (1.0), corpus cold-start `nil`→0.5: score = `0.30 + 0.20 + 0.20 + 0.15 + 0.075 = 0.925 ≥ 0.9` → **auto_accept** (this is why the reference passes today).

After **D4** un-launders `not_assessed` and BEFORE we admit any probe with a real clean producer: the reference integrity verdict is still `not_assessed`, but now D4 maps it to integrity_score **0.5** (not 1.0) — score drops to `0.30·0.5 + 0.20 + 0.20 + 0.15 + 0.075 = 0.775 < 0.9` → the reference would **PARK**. **D4 must NOT un-launder without simultaneously admitting at least one real clean probe (C1) so the reference reaches genuine `trustworthy` (=1.0).** This is the precise coupling. The agreed sequencing that keeps every commit green:

- **D4's un-launder and C1's first real-probe admission ship in ONE ATOMIC commit (M4.8), with the defensive re-tune in the SAME commit.** After C1 admits `mount_boundary` with a working clean producer, the reference integrity verdict becomes genuine `"trustworthy"` (1.0) — back to score 0.925 ≥ 0.9, reference auto-accepts. The reference goes 0.925 (laundered) → [transient, uncommitted] → 0.925 (genuine), never committing 0.775. **No threshold change is needed for C1** if the clean producer yields `passed`. The re-tune is therefore *defensive* (verify the number, don't change it) at C1.

- **Threshold/weights only move in C5**, once the full admitted set is live and A/B/D have also landed their signals, IF the cold-start corpus (0.5) or a deliberately-stricter posture pushes the reference below 0.9. The C5 re-tune is computed against the *frozen reference corpus* (beads_insight + gx), proven to auto-accept, with the exact before/after numbers recorded.

**Re-tune protocol (every slice that could move the reference score):**
1. Run the reference auto-accept proof test (below) BEFORE the change → record reference `score` + `band`.
2. Apply the producer + admission.
3. Run again → record new `score` + `band`. If `band` flipped to `:abstain`, the slice is **not** done — either the clean producer is wrong (returns non-`passed`) or a re-tune is required.
4. If a re-tune is required, change **only** the threshold (preferred) or weights in `@default_thresholds`/`@default_weights` (`trust_score.ex:58-65`), re-run, and assert the reference is back to `:auto_accept` **and** that a known-bad slice (the discrimination broken-signal case) still parks. Record old→new numbers in the commit body and in C5's consolidated table.

---

### THE REFERENCE AUTO-ACCEPT PROOF TEST (shared, created in C1, asserted by every slice)

**File:** `test/conveyor/gate/integrity_reference_autoaccept_test.exs`
**Tag:** `@moduletag :eval` (it builds a real verify pass over `samples/beads_insight`).
**Test name:** `"the known-good reference slice auto-accepts with the live integrity probe set"`

It runs the same fixture as `first_light_production_loop_test.exs` (reuse the helpers), but asserts on the TrustScore band:
```
assert result.output["integrity_verdict"] == "trustworthy"     # was "not_assessed" pre-M4
evidence = Conveyor.Gate.TrustEvidence.from_run_output(result.output)
trust = Conveyor.Gate.TrustScore.evaluate(evidence)
assert trust.band == :auto_accept
assert trust.score >= 0.9
```
This is the **anti-regression spine**: every slice from C1 on must keep this green. The companion `first_light_production_loop_test.exs:87` assertion (`== "not_assessed"`) **must be updated to `== "trustworthy"`** in C1 (it becomes false the moment the first probe is admitted) — flag this as a *required edit*, not an accident.

---

### SLICE C0 — Harden `source_mutation` discrimination (no new producer)

**Goal:** prove the already-live `source_mutation` probe actually parks a slice when production source is mutated mid-run — close the vacuity gap that it's "wired but never exercised end-to-end through the trust gate."

**Why first:** zero new producer, zero re-tune (today `source_mutation` clean → no observation merged on `:local`? No — `source_mutation` IS always merged, `toolchain_runner.ex:229`). On `:local`, `integrity_observations` = `%{"source_mutation" => %{"mutated_production_paths" => mutated}}`. But `verify.ex:10` admits `["hermeticity", "source_mutation"]`, so `source_mutation` **is already in `required_probes`** and **is already evaluated**. On a clean reference, `mutated == []` → `source_mutation` `passed`; with `hermeticity` absent on `:local` → `not_assessed`; fold → `not_assessed`. So `source_mutation` is genuinely live but its *failing* path has no end-to-end-through-trust-gate test. C0 adds it.

**Files/functions:**
- No production change to `toolchain_runner.ex` (the producer is correct).
- **Discrimination test (new):** `test/conveyor/gate/integrity_source_mutation_gate_test.exs`.

**Discrimination test (exact):**
- **Test name (BROKEN signal):** `"a slice that mutates production source during the test run parks (does not auto-accept)"`. Construct a verify run whose pytest mutates a file under `src/` (a fixture test that writes to `src/br_insight/loader.py` during collection). Assert `verification_result["integrity_observations"]["source_mutation"]["mutated_production_paths"] != []`, then `IntegrityEvidence.verdict(obs, required_probes: ["source_mutation"]) == "untrustworthy"`, then `TrustEvidence`→`TrustScore` → `band == :abstain`. **Expected outcome: PARK.**
- **Test name (GOOD signal):** `"the clean reference produces no source mutation and the probe passes"`. The reference run → `mutated_production_paths == []` → probe `passed`. **Expected outcome: ACCEPT** (verdict not `untrustworthy`; with only `source_mutation` admitted and clean → `passed` → fold `trustworthy`).
- **Anti-vacuity guard:** the broken case must assert `band == :abstain` *and* that flipping `mutated_production_paths` back to `[]` in the same evidence yields `band == :auto_accept` (same harness, one field flipped) — proving the gate's verdict is *caused by* the mutation signal, not by an unrelated park.

**Green criteria:** `mix test test/conveyor/gate/integrity_source_mutation_gate_test.exs --seed 0` green; `mix test --exclude eval --seed 0` unaffected (this test is pure-ish — it can run the mutation as a synthetic observation map without a real pytest, preferred, to avoid the `:eval` tag; only the end-to-end variant needs `:eval`). `mix conveyor.eval.scorecard --gate` still shows `sentinel_evasion_rate == 0`.

**br closed:** `C-integrity.0` (create: "source_mutation probe: end-to-end trust-gate discrimination test").

**Risks/traps:** *looks-wired-but-vacuous* — `source_mutation` is the ONLY probe already in `required_probes`, so it's tempting to assume it's tested through the trust gate. It is not: no existing test asserts that a mutated-source slice *parks*. The unit test (`test_integrity_sentinel_test.exs:29-46`) asserts the sentinel verdict but never threads it through `TrustEvidence`/`TrustScore`/the finalizer. C0 closes that.

---

### SLICE C1 — `mount_boundary` producer + admit + (defensive) re-tune

**Goal:** detect any write outside the workspace's writable roots during the run, emit it as the `mount_boundary` observation, admit the probe to the live `required_probes`, and prove a boundary violation parks while the clean reference auto-accepts.

**HARD dependency — the ATOMIC co-ship (M4.8):** **D4** (the integrity un-laundering flip, owned by D, NOT A) MUST land in the SAME atomic commit as C1. See Section 7's re-cut M4.8 and "Re-tuning coordination" below. D4 alone parks the reference (0.775); C1 alone is vacuous (integrity still laundered to 1.0). They co-ship so the reference goes 0.925 → 0.925, never 0.775.

**PRECONDITION GUARD (mechanical — put this assertion at the TOP of C1's discrimination test, so the vacuity-precondition is checkable, not a prose note 2000 lines away):**
```elixir
# C1 is only non-vacuous once D4 has un-laundered integrity. If integrity is
# still laundered to "trustworthy", admitting a probe proves nothing — STOP.
assert Conveyor.Gate.TrustScore.band_of_output(%{}) == :abstain,
  "D4 has NOT landed — integrity is still laundered to auto_accept; C1 admission is vacuous. STOP and co-ship D4."
```
(Use the `A7` helper's `band_of_output/1`. If the assertion fails with `:auto_accept`, D4 is not in this commit; do not proceed.)

**Producer — where & how:**
- Extend `ToolchainRunner` snapshot machinery. `snapshot_source/2` (`toolchain_runner.ex:261-273`) snapshots `src/`. Add `snapshot_outside_writable/2` that snapshots a small, fixed set of **out-of-workspace canary anchors** the run must never touch — but the honest, cheap version is: the workspace path IS the writable root; a "mount boundary violation" is a write to a path the run should not be able to reach. On `:local` we cannot truly sandbox the filesystem, so **`mount_boundary` on `:local` is "genuinely not assessable" → omit the observation → `not_assessed`/non-blocking** UNLESS we adopt the narrower, honestly-measurable definition below.
  - **Honest `:local` definition (chosen):** `write_violations` = production-source files that were **deleted** or files written **outside `src/` but inside the workspace under locked/protected paths** (the same locked-path set `WorkspaceIntegrity` reasons about, `workspace_integrity.ex:48-52`). This is measurable on `:local` via the existing snapshot widened to the locked paths. A write to a locked path during the run is a real, backend-agnostic integrity violation (distinct from the agent's legitimate diff, which is applied *before* verify, exactly like `source_mutation`).
  - **Function:** add to `toolchain_runner.ex`:
    ```elixir
    @spec mount_boundary_observation(before :: map(), current :: map(), locked_paths :: [String.t()]) :: map()
    # returns %{"write_violations" => [paths...]}  (paths under locked_paths touched during the run)
    ```
    Snapshot the locked paths before/after the pytest run (reuse `snapshot_source` generalized to take a root list). Merge into `integrity_observations/2` always (backend-agnostic), like `source_mutation`.
  - `locked_paths` flow into the runner via `opts[:locked_paths]`, threaded from `verify.ex` `runner_opts/1` (new `maybe_put(:locked_paths, get(input, "locked_paths"))`), sourced from the run_spec/contract's protected-path set. If no locked paths are declared, `write_violations == []` (clean) — honest, not vacuous, because "no locked paths to violate" is a true negative.

- **CURRENT behavior → TARGET:**
  - `toolchain_runner.ex:228-235` `integrity_observations/2`: CURRENT merges only `source_mutation` (+ docker hermeticity). TARGET also merges `"mount_boundary" => mount_boundary_observation(...)` (always; backend-agnostic).
  - `verify.ex:10` `@integrity_probes = ["hermeticity", "source_mutation"]` → TARGET `["hermeticity", "source_mutation", "mount_boundary"]`.
  - `first_light_production_loop_test.exs:87` `== "not_assessed"` → TARGET `== "trustworthy"` (reference now has clean `source_mutation` + `mount_boundary` both `passed`, and on `:local` `hermeticity` is absent → `not_assessed`… **WAIT**: with `hermeticity` still in `@integrity_probes` but absent on `:local`, the fold is `not_assessed`, not `trustworthy`).
    - **Trap resolved:** `hermeticity` being in `required_probes` while *unobserved* on `:local` forces `not_assessed` forever. **Fix:** `@integrity_probes` on `:local` must NOT include `hermeticity` (it's docker-only). Make `@integrity_probes` **backend-dependent**: `verify.ex` computes required probes = always-assessable set (`source_mutation`, `mount_boundary`, …admitted) + (`hermeticity` only when `backend == :docker`). This is the "genuinely not assessable on this backend → not in required_probes" taxonomy rule, applied to hermeticity. CURRENT `@integrity_probes` is a module attribute used unconditionally (`verify.ex:30`); TARGET is a `required_probes(backend)` function. **This is a required C1 change** — without it the reference can never reach `trustworthy` on `:local` and every admission is vacuous.

**Re-tune (defensive):** After C1, reference (`:local`) admitted probes = `source_mutation` (clean `passed`) + `mount_boundary` (clean `passed`) → fold `trustworthy` → integrity_score 1.0. With A un-laundered, the reference score returns to `0.925 ≥ 0.9` → auto-accept. **No threshold change.** Record before(A un-laundered, pre-C1)=0.775/abstain → after(C1)=0.925/auto_accept in the commit body. Verify via the reference auto-accept proof test.

**Discrimination test (exact):** `test/conveyor/gate/integrity_mount_boundary_gate_test.exs`
- **BROKEN signal:** `"a run that writes to a locked path parks"`. Observation `%{"mount_boundary" => %{"write_violations" => ["lib/conveyor/core.ex"]}}` (mirrors the trip case `sentinel_fixtures.ex:136-141`). Through `IntegrityEvidence.verdict(obs, required_probes: ["mount_boundary"])` → `"untrustworthy"` → TrustScore `band == :abstain`. **Expected: PARK.** Plus the end-to-end `:eval` variant: a fixture whose pytest writes to a declared locked path → reference run parks.
- **GOOD signal:** `"the clean reference has no write violations and the probe passes"` → `write_violations == []` → `passed` → auto-accept.
- **Anti-vacuity guard:** assert flipping `write_violations` `[] ↔ ["..."]` flips `band` `:auto_accept ↔ :abstain` in the same harness. Assert the BROKEN case produces the specific finding `rule_key == "test_integrity.mount_write_boundary_violation"` (proves the *right* probe fired, not an incidental park).

**Green criteria:**
- `mix test --exclude eval --seed 0` — green (the pure discrimination tests + the `required_probes(backend)` unit test).
- The `:eval` reference auto-accept proof + the `:eval` mount-boundary-violation end-to-end test green.
- `mix conveyor.eval.scorecard --gate` — `sentinel_evasion_rate == 0` (mount_boundary trip case `sentinel_fixtures.ex:136-141` still caught — unchanged, since we did not touch the sentinel).

**br closed:** `C-integrity.1` (create: "mount_boundary producer + live admission + locked-path write detection").

**Risks/traps:**
- *The hermeticity-in-required_probes trap* (above): if you admit `mount_boundary` but leave `hermeticity` unconditionally in `required_probes`, the `:local` reference stays `not_assessed` and the whole exercise is vacuous. Backend-dependent required-probes is mandatory.
- *Over-claiming filesystem isolation on `:local`*: do NOT claim a generic "wrote outside the sandbox" violation on `:local` — we can't sandbox the FS there. Only the locked-path-write definition is honest on `:local`. Generic out-of-sandbox detection is a docker/sandbox concern → sub-stream D.
- *Ordering vs D4 (the atomic co-ship)*: D4 (un-laundering, owned by D) and C1 MUST be in the SAME commit (M4.8). D4 without C1 parks the reference (0.775) → red main; C1 without D4 is vacuous. NOT "co-ship with A" — A does not own the integrity flip. See the PRECONDITION GUARD above.

---

### SLICE C2 — `mapping` producer + admit + re-tune

**Goal:** assert every acceptance criterion the slice covers maps to a (obligation_id, acceptance_ref, interface_oracle_ref) triple; emit `mapping` observation; admit; prove an unmapped obligation parks.

**Producer:** `IntegrityProbes.mapping/2` (pure). Inputs:
- `acceptance_criteria`: from the contract (`samples/beads_insight/conveyor.plan.yml:82-161`); each AC has `key` (→ `acceptance_ref`), `required_test_refs`.
- `obligations`: the obligation/oracle identity. In the loop, the obligation_id + interface_oracle_ref come from the run_spec's contract lock / agent_brief. For M4's width-1 loop the honest source is: **for each acceptance criterion with a `required_test_ref`, the obligation is "AC `key` → test ref(s)" and the interface_oracle_ref is the test ref's stable id** (the locked acceptance test IS the interface oracle in this loop). Build:
  ```
  obligation_refs = for ac <- acceptance_criteria, do:
    %{
      "obligation_id" => "verification_obligation:" <> ac["key"],
      "acceptance_ref" => ac["key"],
      "interface_oracle_ref" => "interface-oracle:" <> hd(ac["required_test_refs"])
    }
  ```
  `mapped_obligation?/1` (`integrity_sentinel.ex:197-200`) requires all three present and non-empty. An AC with **no** `required_test_ref` (or a missing oracle) yields a ref missing `interface_oracle_ref` → `mapped_obligation?` false → probe `failed` → `untrustworthy` (the mapping trip case `sentinel_fixtures.ex:130-135` trips on empty `obligation_refs`).
- **Where called:** `Stations.Verify.run/2` assembles `acceptance_criteria` (already available — `record_evidence` reads it from `AgentBrief`, `record_evidence.ex:41-51`; the verify station can read the same or receive it via station input) and calls `IntegrityProbes.mapping/2`, merging into observations before `IntegrityEvidence.verdict/2`.

**CURRENT → TARGET:**
- `verify.ex` `required_probes(backend)` → add `"mapping"`.
- `verify.ex` `integrity_observations/1` (`:57-58`) currently returns only the runner's `integrity_observations` → TARGET merges `IntegrityProbes.mapping(acceptance_criteria, obligations)`.

**Re-tune:** clean reference → every AC has a `required_test_ref` (verified: all 16 ACs in beads_insight have `required_test_refs`) → all mapped → `passed`. Integrity stays `trustworthy`, score unchanged 0.925. **No threshold change.** Defensive re-tune only.

**Discrimination test (exact):** `test/conveyor/gate/integrity_mapping_gate_test.exs`
- **BROKEN:** `"an acceptance criterion with no interface oracle parks"`. Build `acceptance_criteria` with one AC missing `required_test_refs` → `mapping` observation has a ref missing `interface_oracle_ref` → `verdict == "untrustworthy"` → `band == :abstain`. **PARK.** Finding `rule_key == "test_integrity.obligation_mapping_missing"`.
- **GOOD:** `"the fully-mapped reference passes the mapping probe"` → all ACs mapped → `passed` → auto-accept.
- **Anti-vacuity guard:** flip one AC's oracle present↔absent → `band` flips. Assert empty `obligation_refs` (`[]`) → `failed` (covers the `refs != []` guard at `integrity_sentinel.ex:129`, so an *empty* mapping is `untrustworthy`, not silently `passed` — this is the key vacuity: "no obligations" must NOT pass).

**Green criteria:** `mix test --exclude eval --seed 0` green; reference auto-accept proof green; scorecard `sentinel_evasion_rate == 0`.

**br closed:** `C-integrity.2` (create: "mapping producer + obligation/oracle triple from contract acceptance criteria").

**Risks/traps:**
- *Vacuous mapping*: the sentinel `passed`s only if `refs != [] and all mapped` (`integrity_sentinel.ex:129`). If your producer returns `obligation_refs: []` on a slice with no ACs, that's `failed` (good — fail-closed). But beware producing a *fake* triple (e.g. hardcoding `interface_oracle_ref`) to force `passed` — that's exactly the laundering we're killing. The oracle ref MUST derive from a real `required_test_ref`; if absent, it must be absent.
- *Soft dep on E*: sub-stream E's `AcceptanceMapping` stage already computes per-AC evidence status. If E exposes a cleaner obligation list, C2 should consume it instead of re-deriving from the plan. Coordinate; either source works, but don't double-implement.

---

### SLICE C3 — `required_artifacts` producer (BUILT + proven via static trip cases; NOT admitted to `required_probes` in M4)

> **ANTI-DECORATIVE BRAKE (F23): `required_artifacts` is NOT admitted to the live `required_probes` set in M4.** On the known-good reference the contract declares no required artifacts beyond what verify always emits, so `required==[]` → the probe is a trivial no-op pass — admitting it to `required_probes` would be fail-OPEN-in-disguise (it can never fail for the reference because the reference never exercises a non-trivial requirement). So C3 BUILDS the producer and proves it discriminates via (a) the existing static `SentinelTournament` trip case (already green) and (b) a producer-driven BROKEN-half unit test, but does NOT add `"required_artifacts"` to `verify.ex`'s `required_probes(backend)`. **Live admission is a flagged follow-on** (admit once the loop supplies a real, non-empty required-artifact set for the reference). This removes one slice of decorative live-admission complexity while keeping the discrimination coverage.

**Goal:** BUILD the `required_artifacts` producer and prove it discriminates a missing artifact (via the static trip case + a producer-driven test); do NOT admit it to `required_probes` in M4.

**Producer:** `IntegrityProbes.required_artifacts/2` (pure). Inputs:
- `required`: the contract's required-artifact set. Precedent set: `RunCheck` uses `@required_artifact_paths ["dossier.md", "logs/verification.json"]` (`run_check.ex:22`), overridable via `context[:required_artifact_paths]` (`run_check.ex:63`). Reuse that list (or read from the contract if declared) as the M4 `required`.
- `present`: the artifact projection paths actually recorded. `record_evidence` returns `projection_path` (`record_evidence.ex:27`); the `verify` station also emits a `verification_result` artifact at `verify/result.json` (`verify.ex:20-25`). The honest `present` set is the union of recorded projection paths available at verify time. **Sequencing nuance:** `record_evidence` runs AFTER `verify` (`first_light_production_loop_test.exs:72-79` station order: …`verify`, `record_evidence`). So at verify time the full recorded artifact set isn't known yet.
  - **Resolution:** scope the `required_artifacts` probe to the artifacts the *verify* stage itself is responsible for (the verification log / result.json + the in-run artifacts the runner produced), NOT the post-hoc record_evidence dossier. Define M4 `required = ["verify/result.json"]` (the artifact verify itself emits) plus any verification-log artifact. `present` = the artifacts in `verification_result` + the verify station's own artifact list. This keeps the probe honest and self-contained within verify. The broader run-bundle required-artifact check is `RunCheck`'s job (gate stage 11), not this probe — **do not duplicate it** (brake on complexity).

**CURRENT → TARGET:** build `IntegrityProbes.required_artifacts(required, present)`; the producer + its discrimination tests land, but **do NOT add `"required_artifacts"` to `verify.ex` `required_probes(backend)` in M4** (the static trip case already covers it; live admission is the follow-on). The producer can still be *merged into observations* (so a future flip is one line) without being *required*.

**Re-tune:** none (not admitted to `required_probes`; the reference's band is unaffected). Defensive verify of the reference only.

**Discrimination test:** `test/conveyor/gate/integrity_required_artifacts_gate_test.exs` (unit-level, since the live probe is not admitted — label it as such)
- **BROKEN (producer-driven, NOT a hand-built map fed to verdict):** `"a run missing a required artifact yields untrustworthy"`: drive `IntegrityProbes.required_artifacts(["verify/result.json"], [])` → its observation through `IntegritySentinel.verdict(required_probes: ["required_artifacts"])` → `"untrustworthy"`. Finding `rule_key == "test_integrity.required_artifact_missing"`. (This is the producer's discrimination, asserted at the unit level — it is NOT claimed as a live fail-closed admission on the reference.)
- **GOOD:** `"a run with all required artifacts present"` → present ⊇ required → `passed`.
- **Anti-vacuity guard:** flip `present` to drop the required artifact → verdict flips to `untrustworthy`. The static E8 `SentinelTournament` `required_artifact_missing` trip case is the real anti-vacuity backstop (already green); this unit test proves the producer maps real inputs correctly. Document that `required==[]` → trivial pass is exactly WHY this probe is not admitted live in M4.

**Green criteria:** `mix test --exclude eval --seed 0` green; reference proof green; scorecard `sentinel_evasion_rate == 0`.

**br closed:** `C-integrity.3` (create: "required_artifacts producer built — proven via static trip case + unit test; live admission DEFERRED as a follow-on"). **Follow-on filed:** "Admit `required_artifacts` to live `required_probes` once the loop supplies a real non-empty required-artifact set for the reference" (parent dr1m.1; see H7 br-creation action).

**Risks/traps:**
- *Empty-required vacuity (the reason NOT to admit live in M4)*: `missing = []` when `required = []` → `passed` always (`integrity_sentinel.ex:146-148`). On the reference `required==[]`, so a live admission would be decorative. This is exactly why C3 builds + proves the producer but does NOT flip it into `required_probes` at M4 — the anti-decorative brake.
- *Sequencing trap* (above): do not try to read `record_evidence`'s output at verify time — it hasn't run. Scope to verify-owned artifacts.

---

### SLICE C4 — `falsifier_preservation` + `falsifier_survival` producers (BUILT + proven via static trip cases; NOT admitted to `required_probes` in M4)

> **ANTI-DECORATIVE BRAKE (F23): `falsifier_preservation`/`falsifier_survival` are NOT admitted to the live `required_probes` set in M4.** The beads reference slices may have ZERO falsifier seeds → both probes are `required: false`/empty → trivially `passed` on the reference. Admitting them to `required_probes` would be fail-OPEN-in-disguise (they can never fail for the reference). So C4 BUILDS both producers and proves them discriminate via (a) the existing static `SentinelTournament` `falsifier_dropped`/`falsifier_did_not_survive` trip cases (already green) and (b) producer-driven BROKEN-half unit tests, but does NOT add them to `verify.ex`'s `required_probes(backend)`. **Live admission is a flagged follow-on** (admit once the loop supplies real falsifier seeds for the reference). This removes one slice of decorative live-admission complexity.

**Goal:** BUILD the `falsifier_preservation`/`falsifier_survival` producers and prove they discriminate a dropped/non-surviving seed (via the static trip cases + producer-driven tests); do NOT admit them to `required_probes` in M4.

**Producer:** `IntegrityProbes.falsifier_preservation/1` and `.falsifier_survival/1` (pure), fed by the Test Architect preservation report.
- Source: `Conveyor.TestArchitect.FalsifierPreservation.evaluate!/4` + `Conveyor.Verification.evaluate_falsifier_preservation/2` (confirmed `falsifier_preservation.ex:27`). The report enumerates dropped vs superseded seeds.
- `falsifier_preservation` observation shape (`integrity_sentinel.ex:182-192`): `%{"dropped_falsifier_refs" => [...], "superseded_falsifier_refs" => [...]}`. From the report: dropped = seeds with no preservation; superseded = seeds with a supersession record.
- `falsifier_survival` observation shape (`integrity_sentinel.ex:83-97`): `%{"required" => bool, "survived" => bool, "superseded_by" => ref|nil}`. For M4's width-1 loop, "required" = the slice had compiler falsifier seeds; "survived" = the falsifier test(s) ran red-then-green as designed (the run actually exercised them). If the Test Architect produced no seeds for the slice, `required: false` → `passed` (honest: nothing to survive).

**Where called:** `Stations.Verify` (or a small read in the verify station) obtains the preservation report for the slice's obligations and calls `IntegrityProbes.falsifier_preservation/1` + `.falsifier_survival/1`, merging into observations.

**CURRENT → TARGET:** build `IntegrityProbes.falsifier_preservation/1` and `.falsifier_survival/1`; the producers + their discrimination tests land, but **do NOT add `"falsifier_preservation"`/`"falsifier_survival"` to `verify.ex` `required_probes(backend)` in M4** (the static trip cases already cover them; live admission is the follow-on). Observations may still be merged (so a future flip is one line) without being required.

**Re-tune:** none (not admitted to `required_probes`; the reference's band is unaffected). The reference's falsifier story is genuinely decorative if the reference slice has zero seeds — which is exactly why these are not admitted live in M4; the static E8 trip cases are the real anti-vacuity backstop.

**Discrimination test:** `test/conveyor/gate/integrity_falsifier_gate_test.exs` (unit-level, producer-driven; the live probe is not admitted — label it as such)
- **BROKEN (preservation):** `"a dropped falsifier seed with no supersession parks"`: `dropped_falsifier_refs: ["compiler_falsifier_seed:x"], superseded_falsifier_refs: []` → `verdict "untrustworthy"` → PARK. Finding `rule_key == "test_integrity.falsifier_dropped"` (mirrors `sentinel_fixtures.ex:166-171`).
- **BROKEN (survival):** `"a required falsifier that did not survive parks"`: `%{"required" => true, "survived" => false}` → `verdict "untrustworthy"` → PARK. Finding `rule_key == "test_integrity.falsifier_did_not_survive"`.
- **GOOD:** `"the reference preserves and survives its falsifiers"` → both `passed` → auto-accept.
- **Anti-vacuity guard:** for preservation, assert that a dropped seed which IS in `superseded_falsifier_refs` → `passed` (supersession is the honest escape hatch) and one that is NOT → `failed` (flip the supersession membership → band flips). For survival, flip `survived` true↔false → band flips.

**Green criteria:** `mix test --exclude eval --seed 0` green; reference proof green; `mix conveyor.eval.scorecard --gate` `sentinel_evasion_rate == 0` (the obligation-level `falsifier_seed.dropped` trip in E8 — `sentinel_tournament.ex:84-96` — still caught).

**br closed:** `C-integrity.4` (create: "falsifier preservation + survival producers built — proven via static trip cases + unit tests; live admission DEFERRED as a follow-on"). **Follow-on filed:** "Admit `falsifier_preservation`/`falsifier_survival` to live `required_probes` once the loop supplies real falsifier seeds for the reference" (parent dr1m.1; see H7 br-creation action).

**Risks/traps:**
- *Decorative-on-reference (the reason NOT to admit live in M4)*: if the reference slice has no seeds, both probes pass trivially — admitting them live would be fail-open by construction. That is exactly why C4 builds + proves the producers but does NOT flip them into `required_probes` at M4; the static E8 trip cases are the real anti-vacuity backstop. Do not claim "falsifier integrity is verified live on the reference" — it is not, by design, until the follow-on.
- *Soft dep on Test Architect*: the preservation report must actually be produced for the slice when seeds exist. The live-admission follow-on is gated on the loop surfacing a real report.

---

### SLICE C5 — Consolidated re-tune, reference auto-accept proof, and the falsifier probe (closes the sub-stream)

**Goal:** with C1–C4 (and cross-stream A/B/D) landed, perform the ONE deliberate re-tune of `TrustScore` against the frozen reference corpus, prove zero false-pass on the full canary corpus, and run the external-buggy-commit catch-rate falsifier probe.

**Files/functions:**
- `lib/conveyor/gate/trust_score.ex:58-65` `@default_weights` / `@default_thresholds` — the ONLY place numbers change, and only if the reference falls below 0.9 after all signals are live.
- `lib/conveyor/eval/sentinel_tournament.ex` / scorecard inputs — ensure the static corpus runs in CI gate.

**The re-tune decision (compute, don't guess):** after A/B/D land, the reference evidence is: integrity `trustworthy` (1.0, all admitted probes clean), calibration `:valid` (1.0, A), baseline `:green` (1.0, A), replay `:none` (1.0, B), corpus `cold-start nil`→0.5 OR a real cassette-fidelity rate (secondary decision). Score = `0.30 + 0.20 + 0.20 + 0.15 + 0.15·corpus`. With corpus 0.5 → 0.925 ≥ 0.9 → auto-accept, **no re-tune needed**. With corpus a real rate ≥ 0.5 → still ≥ 0.925. **The re-tune is therefore expected to be a no-op confirmation**; if any signal lands below 1.0 on the reference (e.g. B's replay is `:unknown`=0.5 on a backend that can't replay), recompute and, if the reference drops below 0.9, lower `auto_accept` to the largest value that keeps the reference at auto-accept AND keeps every single-broken-signal case parking. Record the exact before/after in a table in the commit body.

**Re-tune verification (mandatory table in commit + C5 doc):**
| reference corpus | integrity | calib | base | replay | corpus | score | threshold | band |
|---|---|---|---|---|---|---|---|---|
| beads_insight (pre-M4) | 1.0(laundered) | 1.0 | 1.0 | 1.0 | 0.5 | 0.925 | 0.9 | auto_accept |
| beads_insight (post A, pre-C1) | 0.5(not_assessed) | 1.0 | 1.0 | 1.0 | 0.5 | 0.775 | 0.9 | **abstain** ← why C1 co-ships with A |
| beads_insight (post-C1..C4) | 1.0(trustworthy) | 1.0 | 1.0 | 1.0 | 0.5 | 0.925 | 0.9 | auto_accept |
| gx (post-C1..C4) | 1.0 | 1.0 | 1.0 | 1.0 | 0.5 | 0.925 | 0.9 | auto_accept |

(The executor MUST fill the real measured numbers; the table above is the predicted result and the falsifier — if measured numbers differ, the producer is wrong.)

**The full-corpus zero-false-pass proof (HARD exit gate):**
- `mix conveyor.eval.scorecard --gate` over the full canary corpus (beads_insight + gx behavioral references + the E8 static sentinel corpus) must exit 0 with `sentinel_evasion_rate == 0` and every reference slice auto-accepting.
- The reference auto-accept proof test green for BOTH `samples/beads_insight` and `samples/gx`.

**The external-buggy-commit catch-rate falsifier probe (only meaningful post-activation):** introduce planted-defect slices the ADMITTED live probes should catch — e.g. a slice whose patch mutates a locked path → `mount_boundary` (admitted); a slice with an unmapped AC → `mapping` (admitted). Assert each PARKS (does not auto-accept) through the LIVE gate. (Defects whose only honest catch is an un-admitted probe — dropped falsifier seed → `falsifier_preservation`, missing required artifact → `required_artifacts` — are covered by the STATIC E8 `SentinelTournament` trip cases, not the live `required_probes` set, since those probes are not admitted live in M4.) This proves the activated gate catches real planted defects through the live admitted probes, not just synthetic observation maps. **Catch-rate must be 100%** (deterministic, $0). Note: this overlaps the H5 `falsifier/` set — coordinate so C5's live-probe planted defects and H5's 4 fixed targets do not duplicate; C5 proves the IntegritySentinel admitted probes specifically.

**Abstain-fires proof ($0, deterministic):** assert that at least one canary case drives `band == :abstain` deterministically with no Codex call and no network — proving abstain is reachable and free.

**Green criteria (the sub-stream's exit):**
- `mix test --exclude eval --seed 0` — fully green.
- All `:eval` discrimination tests (C0–C4) + the reference auto-accept proof (beads + gx) green.
- `mix conveyor.eval.scorecard --gate` exits 0; `sentinel_evasion_rate == 0`; `sentinel_probe_coverage == 1`.
- Planted-defect catch-rate = 100%.

**br closed:** `C-integrity.5` (create: "consolidated TrustScore re-tune + full-corpus zero-false-pass + planted-defect catch-rate proof"). This slice also contributes to closing `software-factory-ai-dr1m.1` (the producer-side work its comment log defers).

**Risks/traps:**
- *Re-tune theater*: do NOT lower the threshold just to make a number pass. The threshold may only move to accommodate a *real* signal that legitimately scores <1.0 on the reference, and only to a value that still parks every single-broken-signal case. If lowering the threshold would let a broken-signal case auto-accept, the re-tune is wrong.
- *Live-Codex coupling*: the bounded live-Codex pass (first-pass-gate-success / dispute / parked rates) is REPORTED, not a hard gate (ROADMAP warns against coupling milestone exit to agent reliability). Do not gate C5 on a stochastic Codex run.

---

### CONSOLIDATED RISKS / TRAPS (carried forward + added)

1. **The laundering vacuity (carried).** Until **D4** un-launders `not_assessed` in `TrustEvidence.integrity/1` (`trust_evidence.ex:54-56`) — D4 is owned by sub-stream **D**, NOT A — every probe admission is observably a no-op and every discrimination test that asserts "broken → park" is vacuous (the reference auto-accepts regardless). **No probe may be admitted before D4; C1's first admission CO-SHIPS ATOMICALLY with D4 (M4.8).** The PRECONDITION GUARD (`band_of_output(%{}) == :abstain`) at the top of C1's test makes this mechanically checkable. This is the single most important trap.
2. **The hermeticity-in-required_probes trap (added).** `hermeticity` is docker-only; leaving it unconditionally in `verify.ex`'s `required_probes` pins the `:local` verdict to `not_assessed` forever, making every admission vacuous. **`required_probes` must be backend-dependent** (C1). This is a genuine "looks-wired-but-vacuous" hazard — the seed facts list hermeticity as already in `@integrity_probes`, which is exactly the trap.
3. **The result_digest perturbation trap (carried).** Observations merge into `integrity_observations` AFTER the digest (`toolchain_runner.ex:103-108`). Any producer that mutates the digested `result` will break replay (sub-stream B). Always merge into the post-digest key.
4. **Decorative-pass probes (RESOLVED by the anti-decorative admission rule, F23).** `required_artifacts` with empty `required` and `falsifier_*` with no seeds are `passed` trivially on the reference, so they are **NOT admitted to live `required_probes` in M4** (C3/C4 build + prove the producers via the static E8 trip cases + producer-driven unit tests, with live admission flagged as a follow-on). Only `mount_boundary` (C1, real locked-path set) and `mapping` (C2, the 16 beads ACs genuinely exercise the oracle triple) — whose reference produces a NON-trivial measured-good instance — are admitted. The static E8 `SentinelTournament` corpus is the anti-vacuity backstop for the un-admitted probes (it covers all 10 probes' trip cases; `sentinel_probe_coverage == 1` is over the static corpus, not the live `required_probes` set).
5. **Sequencing red-main (added).** C1 must co-ship ATOMICALLY with D4 (same commit, M4.8); D4 without C1 parks the reference (0.775) and C1 without D4 is vacuous. Every slice must keep the reference auto-accept proof green at the commit.
6. **Re-tune theater (added).** Threshold/weights move only to accommodate a real <1.0 signal, only to a value that still parks every broken-signal case. Recorded before/after numbers + a parking check are mandatory.
7. **Cross-stream double-implementation (added).** `mapping` overlaps E's `AcceptanceMapping`; `required_artifacts` overlaps gate-stage `RunCheck`. Consume the canonical source; do not re-derive. Brake on complexity.

---

### CROSS-STREAM DEPENDENCY SUMMARY

- **HARD — ATOMIC with C1 (first admission):** **D4** (un-launder `not_assessed` in `TrustEvidence.integrity/1`, owned by sub-stream **D**). C1 and D4 are the SAME commit (M4.8). Without D4 the entire sub-stream is vacuous; D4 without C1 parks the reference. (Sub-stream A un-launders calibration + baseline and sub-stream B un-launders replay + corpus — separate, earlier concerns — and neither owns the integrity flip.)
- **Soft / data-providing:** sub-stream **E** (WorkspaceIntegrity locked-path set for C1; AcceptanceMapping obligation list for C2).
- **Re-tune coordination (C5):** sub-streams **A** (calibration/baseline live), **B** (replay live → `replay_score` may be 0.5 on non-replay backends), **D** (hidden_dependency/hermeticity-abstain on docker). C5's final threshold is computed only after A/B/D land.
- **Probes explicitly OUT of this sub-stream:** `base_calibration` (→A), `repeatability` (→B), `hidden_dependency` (→D), `hermeticity` (already docker-honest; D owns the docker-availability abstain).

---

## Sub-stream D — Network-isolated / hermetic gate (`docker --network=none`)

**Key:** `D-hermetic-gate`
**Owner intent:** Make the LIVE production gate run its verification inside a `docker --network=none` container, admit `hermeticity` as a REQUIRED integrity probe on the live path, flip the `not_assessed` integrity verdict from fail-OPEN to fail-CLOSED (so an unassessable/non-hermetic run **abstains → parks** instead of auto-accepting), and add a docker-absent ABSTAIN fallback (never a non-hermetic false-pass). Incidentally fixes br `8hx7` (gate pytest provenance from the wrong sample's venv).

**br issues closed:** `8hx7` (non-hermetic venv provenance), and the load-bearing half of `dr1m.1` / `dr1m.1.3` for the hermeticity signal (the integrity verdict becomes a *live, fail-closed* signal on the production loop instead of a laundered no-op). Note: `dr1m.1.3` (BaselineHealth + AcceptanceCalibration vacuous stubs) is owned by other sub-streams; this sub-stream only closes the **integrity/hermeticity** portion.

---

### Verification of seed facts (done before designing — all CONFIRMED, with corrections)

I read every named module. The seed facts are correct in substance; three path/line corrections:

1. **CONFIRMED — no independent gate-side rerun.** `lib/conveyor/stations/verify.ex:13-39` runs `ToolchainRunner.verification_result/3`. `lib/conveyor/gate/stages/test_execution.ex:33-41` consumes the precomputed `verification_result` from context (`serial_driver.ex` line **372**: `verification_result: slice_result.output["verification_result"]`), and only falls back to `VerificationRerunner` when it is absent (`test_execution.ex:43-53`), whose default runner is a no-op exit-0. So there is NO independent gate-side rerun in the live path. **The verify station IS the gate's verification.**

2. **CONFIRMED — backends.** `lib/conveyor/eval/toolchain_runner.ex`: `:local` default at line 61/118/135; `:docker` enforces `--network=` (default `"none"`) at lines 166-174 (run_pytest_cmd) and 193-208 (exec). The honest 6-control hermeticity observation is `hermeticity_observation/1` at lines 241-250 (`network` varies; clock/rng/ordering/locale/shared_state pinned by `--rm` + pinned env). `integrity_observations/2` (lines 228-235) attaches `hermeticity` **ONLY** under `:docker`; under `:local` it is omitted (stays `not_assessed`, non-blocking). `docker_available?/0` exists at lines 128-130 (`System.find_executable("docker") != nil`).

3. **CONFIRMED — verify.ex ALREADY threads backend from station input.** `verify.ex:44-51` (`runner_opts/1`) merges `:backend`, `:network`, `:docker_image`, `:source_root` from the station input when present, defaulting to `:local`. **This is already wired.** The gap is upstream: the *producer of the station input* never sets these keys.

4. **CORRECTED PATH — `RunSpecAssembler` is at `lib/conveyor/planning/run_spec_assembler.ex`** (seed said `run_spec_assembler.ex` generically). The verify-station input is built in `augment_station_plan/6` at **lines 125-130**:
   ```elixir
   "verify" ->
     %{
       "workspace_path" => workspace_path,
       "plan_path" => plan_path,
       "test_refs" => contract.test_pack.required_test_refs
     }
   ```
   It does **NOT** set `backend`/`docker_image`/`network`/`source_root`. **So the live gate is ALWAYS `:local` → hermeticity omitted → `not_assessed`.** CONFIRMED by `test/conveyor/first_light_production_loop_test.exs:84-87`, which asserts the live loop emits `result.output["integrity_verdict"] == "not_assessed"`.

5. **CONFIRMED — THE VACUITY TRAP (load-bearing).** `lib/conveyor/gate/trust_evidence.ex:54-56`:
   ```elixir
   defp integrity(verdict) when verdict in [:suspect, "suspect"], do: "suspect"
   defp integrity(verdict) when verdict in [:untrustworthy, "untrustworthy"], do: "untrustworthy"
   defp integrity(_verdict), do: "trustworthy"      # <-- launders not_assessed AND nil -> "trustworthy"
   ```
   So today a `not_assessed` (or missing) integrity verdict becomes `"trustworthy"`, which `TrustScore.trustworthy?/1` (`trust_score.ex:106`) accepts. **A non-hermetic `:local` run AUTO-ACCEPTS.** Adding docker to the live path *without* this fail-closed fix is pure ceremony. This sub-stream's real deliverable is the fail-closed flip; docker is the *producer* of the asserted-blocked observation that lets the reference still pass after the flip.

6. **CONFIRMED — replay-digest ordering preserved.** `toolchain_runner.ex:103-108`: `result_digest` is computed over `normalized(result)` (`{status, suites}` only) BEFORE `integrity_observations` is attached. A backend switch cannot perturb replay digests. **Must preserve this ordering** (coordinate with sub-stream B). My changes touch only the *opts* passed in, not this ordering, so the property holds by construction — but a discrimination test (Slice D6) asserts the local-vs-docker `result_digest` equality to lock it.

7. **CONFIRMED — br 8hx7.** `verify.ex:45` calls `Workspace.venv_opts()` with **no arg** → `eval/workspace.ex:16` defaults to `samples/tasks_service/.venv` regardless of the slice. Under `:docker` this is MOOT (pytest comes from the pinned image, not a host venv — `run_pytest_cmd(:docker, ...)` ignores `venv_bin`). So moving the gate to `:docker` incidentally fixes 8hx7. The explicit fix (Slice D5) also threads the real workspace path into `venv_opts/1` so the `:local` fallback is hermetic too.

8. **CONFIRMED — env.** `docker` is available (29.4.0, on PATH at `/Users/robertguss/.local/bin/docker`). `unshare` NOT available (Darwin) → DROPPED per decision 3. `NetworkPolicy.docker_args(:none) = ["--network", "none"]` (`network_policy.ex:59`); `:egress` deliberately raises (`network_policy.ex:61-63`). Use the `ToolchainRunner :docker` path, NOT the hardened `DockerRunner` lifecycle.

9. **CONFIRMED — proof already exists at the COMPONENT level, NOT the live path.** `test/conveyor/eval/integrity_discrimination_docker_test.exs` (tagged `:eval`) proves docker-hermetic → `trustworthy` → `:accepted` vs network-open → `untrustworthy` → `:abstained` + slice `:parked`, AND a src-rewriting test → `:abstained`. BUT it calls `ToolchainRunner.verification_result(..., backend: :docker)` **directly** and hand-builds the gate context — it bypasses `RunSpecAssembler` → `RunSlice` → `Stations.Verify` → `serial_driver`/`attempt_loop`. So it proves the *machinery* discriminates, not that the *live production path* drives it. Same for `test/conveyor/eval/integrity_discrimination_live_test.exs` (tagged `:live_agent`). **M4 brings this into the LIVE path** — that is exactly Slice D6.

10. **CONFIRMED — two live TrustEvidence consumers.** `serial_driver.ex:505-506` and `attempt_loop.ex:266-267` both call `TrustEvidence.from_run_output(output)`. The fail-closed flip lives inside `TrustEvidence`, so BOTH paths inherit it with one change. No edits needed in serial_driver/attempt_loop for the flip itself.

11. **CONFIRMED — Finalizer abstain→park.** `finalizer.ex:34-35` (`result.passed? and abstain?(trust)` → `abstain_gate!`), `:68-84` sets `outcome: :abstained` + slice `:park`. The reachable branch is already there.

12. **CONFIRMED — TrustScore numbers (for re-calibration).** `trust_score.ex:58-65`:
    - Weights: `integrity: 0.30, calibration: 0.20, baseline: 0.20, replay: 0.15, corpus: 0.15` (sum 1.0).
    - Threshold: `auto_accept: 0.9`.
    - Hard gate `trustworthy?/1` (`:106-110`): requires `integrity_verdict == "trustworthy"` AND `calibration == :valid` AND `baseline == :green` AND `replay == :none`. Corpus excluded (cold-start safe).
    - Component scores: `integrity_score("trustworthy")=1.0`, `("not_assessed")=0.5`, `("suspect")=0.5`, else `0.0` (`:114-117`). `corpus_score(nil)=0.5` (`:132`).

---

### The re-calibration math (must be stated before any flip; this is the decision-3 requirement)

The known-good reference, run on the **docker** backend with `--network=none`, produces (verified by `integrity_discrimination_docker_test.exs` test 1 + `integrity_evidence_test.exs:42-55`): `integrity_verdict = "trustworthy"`, `calibration = :valid`, `baseline = :green`, `replay = :none`, `corpus = nil`.

`TrustScore.evaluate` →
```
score = 0.30*1.0 (integrity) + 0.20*1.0 (calibration) + 0.20*1.0 (baseline)
      + 0.15*1.0 (replay)   + 0.15*0.5 (corpus nil) = 0.925
```
`0.925 >= 0.9` AND `trustworthy?` true → **`:auto_accept`**. So **after the fail-closed flip, the docker-hermetic reference STILL auto-accepts with NO weight/threshold change.** This is the critical fact: the flip does not require re-tuning, because the docker producer supplies the asserted-`trustworthy` verdict that keeps integrity at 1.0.

Contrast — a `:local` run after the flip: `integrity_verdict = "not_assessed"` → `integrity_score = 0.5`, score `= 0.30*0.5 + 0.925-0.30 = 0.775`, AND `trustworthy?` fails (`"not_assessed" != "trustworthy"`) → **`:abstain`** regardless of score. Correct fail-closed.

**Therefore: weights and threshold are UNCHANGED in this sub-stream.** No re-calibration of numbers is required; the calibration is preserved because D3 (the docker producer) lands FIRST in M4.7 (integrity still laundered, reference at 0.925), and D4's un-laundering co-ships ATOMICALLY with C1's first clean probe admission in M4.8 — so at the flip commit the reference reaches a genuine `trustworthy` (via docker OR via C1's `:local` `mount_boundary`+`source_mutation` with backend-dependent `required_probes`) and stays at 0.925. The `trust_score_test.exs` reference (`reference_evidence/0` with `integrity_verdict: "trustworthy"`, score must be `>= threshold`) continues to pass — verify by running `mix test test/conveyor/gate/trust_score_test.exs` at the M4.8 {D4+C1} commit.

> **Anti-vacuity note on weights:** Do NOT "fix" the local abstain by lowering the threshold or giving `not_assessed` a higher integrity score — that would re-open the fail-open hole. The *only* correct way to make a run auto-accept after the flip is to assert hermeticity via a real docker run. This is the whole point.

---

### Taxonomy this sub-stream relies on (owned by sub-stream A — `A-trust-producers` — coordinate)

Sub-stream A owns the `TrustEvidence` fail-closed taxonomy. This sub-stream is a **consumer** of it and a **producer** of one observation (hermeticity). The principled split (decision 2):

| Situation | Verdict | TrustEvidence mapping | Band |
|---|---|---|---|
| docker run, `--network=none`, all 6 controls satisfied | `trustworthy` | `trustworthy` | auto_accept (if rest green) |
| docker run, network open (`bridge`) | `untrustworthy` | `untrustworthy` | **abstain → park** |
| **`:local` run — producer MISSING but SHOULD be measured** | `not_assessed` | **`not_assessed` (fail-closed, BLOCKING)** | **abstain → park** |
| **docker CLI ABSENT — genuinely not assessable on this backend** | (D2 fallback) | `not_assessed` BUT routed to a NON-blocking band via explicit `docker_unavailable` taxonomy | **abstain → park (parked, $0, no false-pass)** |

The two `not_assessed` rows are distinct in *cause* but **identical in safety outcome: never auto-accept**. Per decision 3, "genuinely not assessable" (docker absent) → `not_assessed`/park (NOT false-pass), distinct from "should be measured but producer missing" which is the same park. The difference matters only for the *operator message* and *metrics taxonomy* (D2 emits a distinct `parked_reason: "hermeticity_backend_unavailable"`), not for the accept decision. **Both fail closed.**

**Hard dependency:** Slice D4 (the flip) requires sub-stream A to have landed the `not_assessed → blocking` change in `TrustEvidence.integrity/1` (or this sub-stream lands it, gated behind a feature flag — see D4 ordering). To avoid a circular dependency we make D4 own the `TrustEvidence` change for the **integrity** signal specifically; sub-stream A owns the **calibration/baseline** clauses and sub-stream B owns the **replay/corpus** clauses. Coordinate the single-file edit to `lib/conveyor/gate/trust_evidence.ex` so we do not collide.

---

### Slice ordering (within this sub-stream)

```
M4.7  D1 (docker_available? hardening) ─┐
      D2 (docker-absent ABSTAIN)        ┼─> D3 (thread backend into RunSpecAssembler, behind opt)
                                        │       (integrity STILL laundered; reference auto-accepts at 0.925)
M4.8  {D4 (flip TrustEvidence integrity fail-closed) + C1 (admit mount_boundary + backend-dependent required_probes)} ATOMIC, ONE commit
                                                │   (reference 0.925 → genuine trustworthy 0.925; NEVER 0.775)
M4.8b D5 (8hx7 venv fix — independent, ≥ D3)
      D6 (LIVE-path discrimination test — requires D3+D4)
      D7 (CI decision + REAL-docker scorecard metric + required hermetic-gate job)
```

Each slice is its own green commit. **REVISED ORDERING (the re-cut master sequence — see Section 7 M4.7/M4.8):** D1, D2, D3 land in **M4.7** (the docker foundation) WHILE integrity is still laundered — D3 alone leaves `:local` runs auto-accepting (the integrity catch-all still launders `not_assessed → "trustworthy"`), so the reference is unmoved at 0.925. Then **D4 co-ships ATOMICALLY with C1 in M4.8** (NOT merely with D3) — D4 un-launders AND C1 admits the first clean `mount_boundary` probe (with backend-dependent `required_probes`) in ONE commit, so the reference reaches a genuine `trustworthy` and never commits the 0.775 parked state. D4 alone would abstain everything; C1's clean probe in the same commit is what keeps the reference green. Then D5, D6, D7 (M4.8b). The safe sequence is: **D1/D2/D3 (docker foundation, integrity still laundered, reference at 0.925) → {D4 un-launder + C1 admit mount_boundary} ATOMIC (reference reaches genuine trustworthy, still 0.925; a `:local` cheat / docker-absent run abstains) → D5/D6/D7.**

---

### Slice D1 — Harden `docker_available?/0` to a real, fast, deterministic probe

**Goal:** `ToolchainRunner.docker_available?/0` must mean "a docker daemon will actually accept `docker run`", not merely "the `docker` binary is on PATH" — otherwise the D2 fallback mis-classifies a present-but-dead daemon as available and the gate hangs/false-passes.

**Current behavior** — `toolchain_runner.ex:128-130`:
```elixir
@spec docker_available?() :: boolean()
def docker_available?, do: System.find_executable("docker") != nil
```
This returns `true` when `docker` is on PATH even if the daemon is down (Docker Desktop stopped) → a subsequent `docker run` raises/blocks.

**Target behavior:** probe the daemon with a cheap, bounded command and cache the result for the process. Add:
```elixir
@doc """
Whether the `:docker` backend is usable: the `docker` CLI is on PATH AND the
daemon answers `docker info`. Cached per-OS-process (the daemon does not appear
mid-run) so the gate pays the ~tens-of-ms probe at most once.
"""
@spec docker_available?() :: boolean()
def docker_available? do
  case :persistent_term.get({__MODULE__, :docker_available?}, :unknown) do
    :unknown ->
      result = probe_docker()
      :persistent_term.put({__MODULE__, :docker_available?}, result)
      result

    cached ->
      cached
  end
end

@doc "Force a re-probe (tests that simulate daemon up/down)."
@spec reset_docker_availability_cache() :: :ok
def reset_docker_availability_cache,
  do: :persistent_term.erase({__MODULE__, :docker_available?})  # via try/rescue if key absent

defp probe_docker do
  with path when is_binary(path) <- System.find_executable("docker"),
       {_out, 0} <- System.cmd(path, ["info", "--format", "{{.ServerVersion}}"],
                      stderr_to_stdout: true) do
    true
  else
    _ -> false
  end
end
```
> **Trap (carry-forward):** `System.cmd` has no built-in timeout; a hung daemon will block `docker info`. Wrap the probe in a `Task.async` + `Task.yield/2`(2_000ms) + `Task.shutdown` so a wedged daemon yields `false`, not a hang. State this explicitly in the executor instructions. Do NOT use `:os.cmd`.

**Where called from:** new call sites in D2/D3 (`RunSpecAssembler` decides backend) and the existing direct callers (none in lib today besides tests — `grep "docker_available?"` shows only the spec). Keep `:persistent_term` rather than a GenServer (no process to own; pure cache).

**DISCRIMINATION TEST(S):** `test/conveyor/eval/toolchain_runner_docker_available_test.exs` (tagged `:eval` only if it actually shells out; the daemon-down case can be unit-tested by injecting the probe).
- Refactor `probe_docker` to accept an injectable command runner: `docker_available?(probe_fun \\ &default_probe/0)`. Then:
  - **BROKEN-signal case** — `test "daemon down -> false (no false-available)"`: inject a probe returning `{:error, ...}` (binary present, `docker info` exits 1) → assert `docker_available?(fn -> false end) == false`. This proves the gate will ABSTAIN (via D2), not false-pass, when docker is dead.
  - **GOOD-signal case** — `test "daemon up -> true"`: inject `fn -> true end` → `true`.
  - **REAL case** (`:eval`) — `test "real daemon answers"`: on this dev box (docker 29.4.0 up) asserts `docker_available?() == true`. In CI without docker it asserts `false` (do NOT hardcode `true`).

**Re-calibration:** none (no TrustScore change).

**Green criteria:** `mix test test/conveyor/eval/toolchain_runner_docker_available_test.exs --seed 0` green; `mix test --exclude eval --seed 0` green (the injected cases run without docker).

**Dependencies:** none. First slice.

**Risks/traps:** (a) the hang-without-timeout trap above; (b) `:persistent_term` caching means a test that toggles daemon state must call `reset_docker_availability_cache/0` in `setup` — document it; (c) do not let the probe’s `System.cmd` inherit a polluting env.

---

### Slice D2 — Docker-absent ABSTAIN fallback (never a non-hermetic false-pass)

**Goal:** When the gate is configured to run hermetically but docker is unavailable, the run must **park (abstain), at $0, deterministically** — NOT silently fall back to `:local` and auto-accept. This is the "genuinely not assessable on this backend" taxonomy branch (decision 3).

**New module:** `Conveyor.Gate.HermeticBackend`
- **Responsibility:** centralize the policy decision "given the slice's hermeticity requirement and the host, what backend opts (if any) does the verify station get, and if none, what abstain signal do we emit?". Single source of truth so `RunSpecAssembler` (D3) and any future caller agree.
- **Key signatures:**
  ```elixir
  @type decision ::
          {:docker, keyword()}          # use docker with these runner opts
          | {:local, keyword()}         # explicit local (hermeticity not required for this slice)
          | {:unavailable, String.t()}  # require hermetic, docker absent -> abstain reason

  @doc "Decide the verify-station backend for a slice attempt."
  @spec decide(keyword()) :: decision()
  def decide(opts)
  # opts: :require_hermetic (bool, default true for M4 live gate),
  #       :docker_image (String), :network ("none" default), :source_root ("src" default),
  #       :docker_available? (bool, default ToolchainRunner.docker_available?())  # injectable

  @doc "The station-input keys to merge for a decision (or %{} for :unavailable)."
  @spec station_input(decision()) :: map()
  def station_input({:docker, opts}), do: %{"backend" => "docker", "network" => opts[:network] || "none",
                                            "docker_image" => opts[:docker_image], "source_root" => opts[:source_root] || "src"}
  def station_input({:local, _}), do: %{}            # local default, no keys
  def station_input({:unavailable, _reason}), do: %{} # no verify backend; abstain handled separately
  ```
- **The abstain mechanism for `:unavailable`:** we do NOT want to run pytest at all (it would produce a passing `:local` result that launders to accept). Instead, when `decide/1` returns `{:unavailable, reason}`, `RunSpecAssembler` (D3) injects a station-input key `"hermetic_backend_unavailable" => reason` into the verify station, and `Stations.Verify` (D3 change) detects it and emits `"integrity_verdict" => "not_assessed"` with an explicit `parked_reason`, so `TrustEvidence` (post-D4) maps it to a blocking integrity signal → abstain → park. **Crucially it still runs the suite for the gate stages (so a genuinely-broken patch still hard-fails), but it CANNOT auto-accept** because integrity is `not_assessed` and fail-closed. The `parked_reason: "hermeticity_backend_unavailable"` is carried into the output for the operator inbox (sub-stream owning the inbox reads it).

  > **Design choice (baked, overridable by Robert):** on docker-absent we still run the `:local` suite (so the gate can still *reject* a broken patch and report a real test result), but force integrity `not_assessed` so it can never *accept*. The alternative — refuse to run at all — is safer-looking but throws away the ability to catch hard failures cheaply. Both park a green run; only the "broken patch + docker absent" case differs, and running it is strictly more informative. **Flag for Robert.**

**Where called from:** `RunSpecAssembler.augment_station_plan/6` (D3).

**DISCRIMINATION TEST(S):** `test/conveyor/gate/hermetic_backend_test.exs` (unit, no docker — `:docker_available?` injected):
- **BROKEN-signal case** — `test "require_hermetic + docker absent -> {:unavailable, reason}"`: `decide(require_hermetic: true, docker_available?: false)` → `{:unavailable, "hermeticity_backend_unavailable"}`. Asserts `station_input/1` does NOT inject `backend=docker`, AND that the abstain key is present (asserted in D3's integration test). Proves the gate **abstains**, not false-passes, when docker is absent.
- **GOOD-signal case** — `test "require_hermetic + docker present -> {:docker, opts}"`: `decide(require_hermetic: true, docker_available?: true, docker_image: "img")` → `{:docker, _}` and `station_input/1` injects `"backend" => "docker"`, `"network" => "none"`. Proves the gate accepts the hermetic path.
- **Edge** — `test "require_hermetic: false -> {:local, _} (opt-out path unchanged)"`: ensures non-M4 callers (e.g. existing unit tests that don't want docker) still get `:local`.

**Dockerless-CI `hermetic_abstain_proof` metric (the gate where it MATTERS — $0, blocking, runs on the dockerless runner):** the docker-absent abstain path is the one that must hold on the runner that has no docker, yet D7's `hermetic_false_pass_rate` is emitted only from the docker job. To close the "unit-tested but not gated where it matters" gap, D2 ships a **deterministic, $0, blocking `hermetic_abstain_proof` scorecard metric** that drives the docker-absent path (injected `docker_available?: false`) through the **REAL** assembler → verify → finalizer chain and asserts the run persisted `:abstained` (NOT auto-accepted). It writes `eval/scorecards/inputs/hermetic_abstain_proof.json` with `value: 0` (false-pass count) ONLY when the injected-docker-absent run abstained; `> 0` (a false-pass) reddens `--gate`. This runs on the dockerless main CI job (it injects unavailability, needs no real docker), so "docker-absent abstains" is GATED on the runner where it actually matters — not merely unit-tested. (This is the metric form of D6's docker-absent case + F7's abstain proof; make it a hard scorecard metric, not just a test.)

**Re-calibration:** none.

**Green criteria:** `mix test test/conveyor/gate/hermetic_backend_test.exs --seed 0` green; `mix test --exclude eval --seed 0` green; the `hermetic_abstain_proof` metric emits `value: 0` on the dockerless runner and `--gate` stays healthy; a planted "docker-absent auto-accepts" fixture flips it `> 0` and reddens `--gate`.

**Dependencies:** D1 (uses `docker_available?/0`). Within this slice: ships before D3.

**Risks/traps:** (a) **The biggest trap is making `:unavailable` silently degrade to `{:local, _}`** — that re-creates the false-pass. The test BROKEN case exists precisely to forbid that; the executor must assert `{:unavailable, _}`, not `{:local, _}`. (b) Default `require_hermetic` must be `true` for the M4 live gate but `false`/opt-in for the existing unit-test loop fixtures, or every existing `:local` unit test starts abstaining — see D3 for how the default is scoped (it is an explicit `RunSpecAssembler` opt, not a global).

---

### Slice D3 — Thread `backend=docker` into the production verify station (gated)

**Goal:** Make `RunSpecAssembler` produce a verify-station input carrying the hermetic backend opts (or the docker-absent abstain key), so the LIVE `Stations.Verify` runs in docker and emits an asserted hermeticity observation.

**File:** `lib/conveyor/planning/run_spec_assembler.ex`.

**Current behavior** — `augment_station_plan/6`, lines 125-130 (verify branch) sets only `workspace_path`/`plan_path`/`test_refs`.

**Target behavior:** thread the `HermeticBackend.decide/1` result. Add an opt `:hermetic_gate` (default behavior decided below) to `assemble!/2` so callers control it; merge the station-input keys:
```elixir
"verify" ->
  base = %{
    "workspace_path" => workspace_path,
    "plan_path" => plan_path,
    "test_refs" => contract.test_pack.required_test_refs
  }
  decision = HermeticBackend.decide(hermetic_opts(opts, workspace_path))
  base
  |> Map.merge(HermeticBackend.station_input(decision))
  |> maybe_put_unavailable(decision)   # injects "hermetic_backend_unavailable" => reason for {:unavailable, _}
```
with
```elixir
defp hermetic_opts(opts, workspace_path) do
  [
    require_hermetic: Keyword.get(opts, :hermetic_gate, default_hermetic_gate?()),
    docker_image: Keyword.get(opts, :docker_image),       # nil -> ToolchainRunner @docker_image default
    network: "none",
    source_root: Keyword.get(opts, :source_root, "src")
  ]
end
```

**The `default_hermetic_gate?/0` decision (baked, overridable by Robert):**
- **Recommendation: default `false` in `RunSpecAssembler`, opt-in `hermetic_gate: true` at the call sites that matter (the live demo / first-light loop / the D6 test).** Reasoning: hundreds of existing unit/integration tests assemble RunSpecs with map-fakes and no docker; flipping the global default to `true` would either (a) make them all try docker (slow, and many run in environments without the image) or (b) make them all abstain (red). The safe, incremental posture (decision 2 — "stay green at EVERY commit") is to keep the default OFF and turn it ON explicitly where we have a real workspace + image. The runner-up — global default `true` with a `:local` opt-out everywhere — is more "fail-closed by default" but violates green-at-every-commit and is a large blast radius. **Flag for Robert: do we want the live production conductor (not tests) to pass `hermetic_gate: true`? Recommendation: YES — the conductor’s real assemble! call site sets it true; tests stay false.** Identify the conductor call site (the production loop entry, e.g. the job/CLI that runs a real slice) and set `hermetic_gate: true` there in D3.

> **Why this is still fail-closed and not a cop-out:** with `hermetic_gate: false`, `:local` runs emit `not_assessed`; **after D4** that abstains anyway. So even an "off" gate cannot auto-accept a non-hermetic run once D4 lands. The `hermetic_gate` flag only chooses *whether to attempt docker*; it does not choose whether a non-hermetic result can auto-accept (it never can, post-D4). The flag's real job is to avoid running docker in test environments that can't, while still parking them. This is the cleanest reading of "incremental fail-closed."

**`docker_image` for the live samples:** `ToolchainRunner` defaults to the pinned `ghcr.io/conveyor/sample-python-runner@sha256:...` image. For beads_insight/gx the existing docker tests build a `conveyor/beads-insight-runner:local` image on demand. **Decision (baked):** the production assemble! call passes `docker_image` derived from the project (a new `Project.runner_image` field is out of scope for D-hermetic; for now thread an explicit `:docker_image` opt at the call site, defaulting to the pinned image). Flag: a per-project runner image registry is a follow-on (note in risks). For beads_insight/gx the D6 test builds the local image exactly as the existing docker test does.

**Where called from:** the production conductor entry point (set `hermetic_gate: true`), and the D6 test.

**DISCRIMINATION TEST(S):** extend `test/conveyor/planning_run_spec_assembler_test.exs` (unit, `docker_available?` injectable via the `HermeticBackend` opt path — pass a fake through `assemble!` opts, or use a `:hermetic_gate`-on + injected availability):
- **BROKEN-signal case** — `test "hermetic_gate + docker absent -> verify input carries abstain key, NO docker backend"`: assemble with `hermetic_gate: true` and an injected `docker_available?: false`; assert the verify station input has `"hermetic_backend_unavailable"` set AND does NOT have `"backend" => "docker"`. Proves docker-absent → abstain wiring, not false-pass.
- **GOOD-signal case** — `test "hermetic_gate + docker present -> verify input has backend=docker, network=none, source_root"`: inject `docker_available?: true`; assert `input["backend"] == "docker"`, `input["network"] == "none"`, `input["source_root"] == "src"`.
- **Regression guard** — `test "hermetic_gate off (default) -> verify input unchanged (no backend key)"`: the existing assertions on the verify input still hold; no `backend` key. Proves we did not break the existing `:local` loop.

**Re-calibration:** none in D3 (D3 alone changes only *what backend the producer uses*; the laundering in `TrustEvidence` is untouched, so `:local` and docker-hermetic both still auto-accept the reference at this commit — green preserved). The flip is D4.

**Green criteria:**
- `mix test --exclude eval --seed 0` green (the unit assembler tests + all existing tests; default-off means no behavior change for them).
- `mix test test/conveyor/first_light_production_loop_test.exs --seed 0` (it's `:eval`) — **must still pass with `integrity_verdict == "not_assessed"`** because that test does NOT pass `hermetic_gate: true` (it stays `:local`). If you choose to flip that test to docker, do it in D6, not D3.

**Dependencies:** D1, D2. Coordinate the `lib/conveyor/planning/run_spec_assembler.ex` edit (no overlap with other sub-streams expected, but A touches TrustEvidence — different file).

**Risks/traps:** (a) **`container_image_ref`/`container_image_digest` in `run_spec_attrs/8` (lines 192-198) are unrelated metadata fields** — do NOT confuse them with the runtime `docker_image` opt; the runtime image is a verify-station *input* key, not the RunSpec attr. (b) Threading `source_root: "src"` is required for the docker `source_mutation` snapshot to find the right dir (both beads_insight and gx use `src/`). (c) If `docker_image` is nil at the call site, ToolchainRunner falls back to the pinned ghcr image which may not exist locally → docker run fails → the gate would error, not abstain. **Trap:** an *erroring* docker run is worse than an absent one. Mitigation: `HermeticBackend.decide` only returns `{:docker, _}` when `docker_available?` is true AND (recommended) when an image ref is resolvable; if the image cannot be pulled the run errors. Document that the live call site must ensure the image exists (the D6 test builds it; the production conductor must pre-pull/build). Consider a follow-on `image_available?/1` check — flag as a risk, not in-scope.

---

### Slice D4 — Flip the integrity signal fail-CLOSED (land WITH D3's docker producer)

**Goal:** Stop laundering `not_assessed`/`nil` integrity to `"trustworthy"`. Make an unassessed integrity verdict abstain. Land this in the SAME change-set as D3's docker producer so the known-good reference (now docker-hermetic) still auto-accepts at this commit.

**File:** `lib/conveyor/gate/trust_evidence.ex`.

**Current behavior** — `trust_evidence.ex:54-56`:
```elixir
defp integrity(verdict) when verdict in [:suspect, "suspect"], do: "suspect"
defp integrity(verdict) when verdict in [:untrustworthy, "untrustworthy"], do: "untrustworthy"
defp integrity(_verdict), do: "trustworthy"       # launders not_assessed AND nil
```

**Target behavior** — separate the three cases; `not_assessed` and `nil` become blocking:
```elixir
defp integrity(verdict) when verdict in [:suspect, "suspect"], do: "suspect"
defp integrity(verdict) when verdict in [:untrustworthy, "untrustworthy"], do: "untrustworthy"
defp integrity(verdict) when verdict in [:trustworthy, "trustworthy"], do: "trustworthy"
# Fail-closed: a missing/unassessed integrity verdict is NOT trustworthy. It maps
# to "not_assessed" which TrustScore.trustworthy?/1 rejects -> abstain -> park.
# (Was previously laundered to "trustworthy" — the M3-era fail-OPEN bootstrap.)
defp integrity(_verdict), do: "not_assessed"
```

**Why this is safe at this commit (the ATOMIC M4.8 co-ship):** `TrustScore.integrity_score("not_assessed") = 0.5` and `trustworthy?/1` requires exactly `"trustworthy"`. So:
- docker-hermetic reference → verdict `"trustworthy"` → still auto-accepts (score 0.925, gate passes). **Reference preserved.**
- **`:local` reference → reaches `"trustworthy"` BECAUSE C1 co-ships in THIS commit** — C1 admits `mount_boundary` + makes `required_probes(backend)` backend-dependent (hermeticity only under `:docker`), so the `:local` reference's clean `source_mutation` + `mount_boundary` fold to a genuine `trustworthy` (1.0), auto-accepting at 0.925. This is why D4 and C1 are ATOMIC: D4 alone would drop the `:local` reference to `not_assessed` (0.5) → 0.775 → park; C1's clean probe in the same commit supplies the genuine `trustworthy`.
- `:local` non-hermetic-CHEAT / docker-absent run → verdict `"not_assessed"` → abstain. **Fail-closed achieved.**

> **CRITICAL ORDERING (decision 2 — never park the known-good reference; the ATOMIC M4.8 co-ship):** D4 MUST land in the SAME commit as **C1** (the first clean probe admission + backend-dependent `required_probes`) — and after D1/D2/D3 (the docker foundation, landed in M4.7 while integrity was still laundered). D4 alone drops the reference to 0.775 → park; C1 alone is vacuous. Co-shipped, the reference goes 0.925 → [transient] → 0.925, never 0.775. For the first-light loop test specifically, two acceptable strategies:
> 1. **(Recommended)** In the same commit, update `first_light_production_loop_test.exs` to drive the docker backend (`hermetic_gate: true` + build the local image, mirroring the docker discrimination test) so it asserts `integrity_verdict == "trustworthy"` and still auto-accepts. This makes the live loop genuinely hermetic. Move the now-changed assertion (`"not_assessed"` → `"trustworthy"`) here.
> 2. Keep that test `:local` but assert it now ABSTAINS (parked) — honest, but it stops being a "passes the gate" demo. Recommendation: strategy 1, because the milestone goal is a hermetic live gate, and the test should demonstrate it.

**Coordinate with sub-streams A and B:** A owns the **calibration/baseline** `TrustEvidence` mappings and B owns the **replay/corpus** mappings. The `integrity/1` clause is owned HERE (D4). Land them so the single file is edited once per sub-stream without conflict (sequence A/B then D; agree on order). The `assemble/1` default in `TrustEvidence` (`trust_evidence.ex:50-59`) and its test (`trust_evidence_test.exs:50-59`) currently encode the fail-OPEN defaults — those defaults are about *no signal at all*; D4 only changes the **integrity** clause, so the `assemble(%{})` default for integrity changes from `"trustworthy"` to `"not_assessed"`. **This breaks two existing tests that MUST be updated:**

**Existing tests this slice MUST change (and HOW):**
1. `test/conveyor/gate/integrity_evidence_test.exs:12-17` — `"not_assessed is non-blocking once it reaches TrustEvidence"` asserts `evidence.integrity_verdict == "trustworthy"`. **Change to assert `== "not_assessed"`** and rename to `"not_assessed is BLOCKING once it reaches TrustEvidence (fail-closed)"`. This test currently *encodes the vacuity* — it must be inverted. This is the canonical anti-vacuity flip.
2. `test/conveyor/gate/trust_evidence_test.exs:45-47` — `"empty / unmeasured output is non-blocking (auto-accept)"` asserts `band(%{}) == :auto_accept`. **Change to `:abstain`** (because empty output now yields `not_assessed` integrity → abstain). Rename to `"empty / unmeasured output abstains (fail-closed)"`.
3. `test/conveyor/gate/trust_evidence_test.exs:50-59` — `assemble(%{})` expected map asserts `integrity_verdict: "trustworthy"`. **Change to `integrity_verdict: "not_assessed"`.**

> These three edits ARE the proof the flip happened. Do not skip them. Each is an anti-vacuity inversion: the test that proved the gate stayed green on no-signal now proves it abstains on no-signal.

**DISCRIMINATION TEST(S):** add `test/conveyor/gate/trust_evidence_test.exs` cases:
- **BROKEN-signal case** — `test "not_assessed integrity verdict abstains (fail-closed flip)"`:
  ```elixir
  assert band(%{"integrity_verdict" => "not_assessed",
                "test_pack_calibration" => %{"status" => "valid"},
                "baseline_health_status" => "passed"}) == :abstain
  ```
  Proves the gate FAILS-CLOSED on an unassessed run even when calibration+baseline are green.
- **GOOD-signal case** — `test "explicit trustworthy integrity (docker-hermetic) auto-accepts"`:
  ```elixir
  assert band(%{"integrity_verdict" => "trustworthy",
                "test_pack_calibration" => %{"status" => "valid"},
                "baseline_health_status" => "passed"}) == :auto_accept
  ```
  Proves the docker producer's asserted verdict still accepts.

**Re-calibration:** **No weight/threshold change.** State explicitly in the commit message: weights `integrity:0.30 calibration:0.20 baseline:0.20 replay:0.15 corpus:0.15` and threshold `0.9` UNCHANGED before/after. Verification that the known-good reference still auto-accepts: `mix test test/conveyor/gate/trust_score_test.exs --seed 0` (the `reference_evidence/0` test, score `0.925 >= 0.9`) stays green — run it and confirm. AND the docker discrimination test (`integrity_discrimination_docker_test.exs` test 1) still asserts `:accepted` — run it (`:eval`, docker present) and confirm.

**Green criteria:**
- `mix test --exclude eval --seed 0` green AFTER updating the 3 inverted tests above. (If any test other than those 3 goes red, you have found a *second* place that depended on the laundering — investigate; it may be a real additional vacuity to fix or coordinate with sub-stream A.)
- `mix test test/conveyor/gate/trust_score_test.exs --seed 0` green (reference auto-accepts).
- `:eval`, docker present: `mix test test/conveyor/eval/integrity_discrimination_docker_test.exs --seed 0` green (all 3 cases).

**Dependencies:** D1/D2/D3 (the docker foundation, landed first in M4.7), and **C1 (the first clean probe admission — co-ships ATOMICALLY with D4 in M4.8, NOT paired merely with D3)**. Sub-stream A coordinates the OTHER `trust_evidence.ex` clauses (calibration/baseline/replay/corpus) — A does NOT touch the integrity clause, which D4 owns. The single-file edit to `trust_evidence.ex` is split: A owns calibration/baseline (and B owns replay/corpus), D4 owns integrity — sequence so the file is edited without conflict.

**Risks/traps:** (a) **The whole-suite trap:** flipping `integrity(_) -> not_assessed` may red OTHER tests that unknowingly relied on no-integrity-signal auto-accepting (e.g. some production-loop `:eval` tests, or sub-stream-A-owned signals). Each such red is either (i) a test that must be updated to drive docker, or (ii) a real second vacuity. **Do a full `mix test` (incl `:eval`, docker present) sweep and triage every red — do not blanket-update tests to make them green; that would re-launder the vacuity in the test layer.** (b) `attempt_loop.ex` and `serial_driver.ex` both consume the flipped `TrustEvidence` — confirm their `:eval` production-loop tests (`m1_codex`/`m2_rework`/`m3_skip` production loop tests) either drive docker or now assert abstain; check `grep -l "integrity_verdict\|auto_accept\|accepted" test/conveyor/m*_production_loop_test.exs` and triage. (c) Sub-stream B's replay digest: unaffected (D4 touches no digest path), but the paired test must still show `result_digest` stable across backends (covered in D6).

---

### Slice D5 — Fix br 8hx7 (gate pytest venv resolved from the wrong sample)

**Goal:** Make the `:local` fallback's pytest venv come from the slice's OWN workspace `requirements.lock`, not the hardcoded `samples/tasks_service/.venv`. (Under docker this is already moot; this hardens the `:local` path so it is at least *correct*, even though post-D4 it abstains.)

**File:** `lib/conveyor/stations/verify.ex`.

**Current behavior** — `verify.ex:45`:
```elixir
Workspace.venv_opts()      # no arg -> defaults to samples/tasks_service/.venv (workspace.ex:16)
```
This returns `[venv_bin: ".../samples/tasks_service/.venv/bin"]` regardless of the slice → gate pytest runs from the WRONG sample's venv.

**Target behavior:** pass the slice's workspace path so `venv_opts/1` looks for `<workspace>/.venv/bin`, and fall back to building a venv from the workspace's own `requirements.lock` (ToolchainRunner already does this when no `venv_bin` is given). Concretely:
```elixir
defp runner_opts(input) do
  workspace_path = get(input, "workspace_path")
  Workspace.venv_opts(workspace_path)               # <-- pass the real workspace
  |> Keyword.merge(test_refs: get(input, "test_refs") || [])
  |> maybe_put(:backend, backend(get(input, "backend")))
  |> ...
end
```
`eval/workspace.ex:16` `venv_opts(sample_path)` already accepts a path and returns `[venv_bin: "<path>/.venv/bin"]` if that dir exists, else `[]` (→ ToolchainRunner builds+caches from `<workspace>/requirements.lock`). So passing `workspace_path` is the fix. Both beads_insight and gx have `requirements.lock` (`pytest==9.1.0` etc.), so the build path works; they have no committed `.venv`, so the build-from-lock branch fires (correct).

> **Note:** post-D4, a `:local` run abstains anyway, so 8hx7's *trust* impact is neutralized by the flip. But the fix is still correct and required by the issue, and it makes the docker-absent `:local` *suite result* (which the gate stages still consume, per D2's design choice) provenance-correct. Land it.

**DISCRIMINATION TEST(S):** `test/conveyor/stations/verify_test.exs` (new; tagged `:eval` because it runs pytest):
- **BROKEN-signal case** — `test "venv resolves from the slice workspace, not samples/tasks_service"`: set up a beads_insight workspace (no `.venv`); run the verify station `:local`; assert it builds a venv keyed off the beads_insight `requirements.lock` digest and that pytest collects beads_insight tests (e.g. `tests/test_loader.py` ids appear), NOT tasks_service tests. The pre-fix behavior would resolve `samples/tasks_service/.venv` and run with the wrong pytest provenance — assert the workspace path is the one threaded in (you can assert via the venv cache key or by collecting only beads tests). If a committed tasks_service venv is present, the BROKEN case is: pre-fix uses it; post-fix ignores it.
- **GOOD-signal case** — the same run succeeds with the correct suite and `verification_result["status"] == "passed"` for the reference patch.

> Anti-vacuity: assert the *negative* — that tasks_service node-ids do NOT appear — so the test fails if the wrong venv/sample leaks back in.

**Re-calibration:** none.

**Green criteria:** `mix test test/conveyor/stations/verify_test.exs --seed 0` (`:eval`) green; `mix test --exclude eval --seed 0` green (no regression).

**Dependencies:** none hard; can land after D3 (independent file). Order it ≥ D3 so the verify-station changes don't conflict.

**Risks/traps:** (a) if any existing `:eval` test relied on the tasks_service venv being picked up implicitly when running a tasks_service slice, this is still correct because `venv_opts(workspace_path)` for a tasks_service workspace finds `.venv` there. (b) building a venv from lock requires network for `pip install` on first run — but the gate is hermetic; in practice the venv is pre-built/cached, or under docker this path is unused. Document that the `:local` venv-build needs network (acceptable: `:local` is the non-hermetic, soon-abstained fallback, not the hermetic gate).

---

### Slice D6 — LIVE-path hermetic discrimination test (the milestone proof)

**Goal:** Prove end-to-end that the **production path** (`RunSpecAssembler` → `RunSlice` → `Stations.Verify` → gate → `serial_driver`/`Finalizer`) discriminates: a docker-hermetic reference auto-ACCEPTS; the same run with the network open ABSTAINS + parks; and (NEW) a docker-absent run PARKS rather than false-passes. This is what the existing component-level docker test does NOT cover (it bypasses the assembler/stations).

**New test:** `test/conveyor/eval/integrity_discrimination_live_path_test.exs` (tagged `:eval`, `async: false`, `use Conveyor.DataCase`). It mirrors `integrity_discrimination_docker_test.exs` BUT drives the real `RunSpecAssembler.assemble!(..., hermetic_gate: true, docker_image: @image, source_root: "src")` and runs `RunSlice.run!` so the verify station itself selects docker (Slice D3 wiring), then finalizes via the real `serial_driver`/`Finalizer` path (or `RunGate.run_gate_only!` + `Finalizer.finalize!` with `TrustEvidence.from_run_output(result.output)` — using the REAL `result.output`, not a hand-built map). It builds the `conveyor/beads-insight-runner:local` image on demand exactly as the existing docker test (`ensure_image!`).

**Cases:**
- **GOOD (accept):** `test "live production path: docker-hermetic reference -> trustworthy -> accepted"` — assemble with `hermetic_gate: true`, network `none`; run the loop; assert `result.output["integrity_verdict"] == "trustworthy"`, gate passes, finalize → `run_attempt.outcome == :accepted`, slice NOT parked. This is the reference auto-accept on the LIVE path (closes the loop the existing tests left open).
- **BROKEN (abstain) — network open:** `test "live production path: network-open -> untrustworthy -> abstained + parked"` — same assemble but force `network: "bridge"` (thread a `:network` override down to the verify station). Assert `integrity_verdict == "untrustworthy"`, finalize → `:abstained`, slice `:parked`.
- **BROKEN (abstain) — docker absent:** `test "live production path: docker unavailable -> not_assessed -> abstained + parked (no false-pass)"` — inject `docker_available?: false` (via the `HermeticBackend` opt path through `assemble!`); assert the verify station emitted `not_assessed`, finalize → `:abstained`, slice `:parked`. **This is the D2 fallback proven end-to-end — the most important anti-vacuity case: docker-absent must PARK, never auto-accept.**
- **(Optional, mirrors existing) src-rewrite cheat → abstain:** plant the cheating test (as `integrity_discrimination_docker_test.exs:166-173`) and assert `source_mutation` → untrustworthy → abstain. Confirms `source_mutation` still fires on the live path.
- **INVARIANT (docker-absent fail-closed is NOT rescuable by other green signals):** `test "docker unavailable parks even when ALL other signals are good"` — inject `docker_available?: false` AND a reference with calibration `:valid`, baseline `:green`, replay `:none`, corpus high — assert the run STILL `:abstained`/`:parked`. This pins the guarantee that the docker-absent `not_assessed` integrity fail-closed cannot be overridden by other green signals (the latent footgun if a future caller passes `integrity_verdict` explicitly while docker is absent). The abstain comes from `trustworthy?/1` requiring `integrity == "trustworthy"`, which a docker-absent run can never supply.

**The anti-vacuity backbone of this test:** it must assert BOTH that the good case ACCEPTS and that EACH broken case ABSTAINS+PARKS *through the real assembler/station wiring*. A test that only asserts the accept case would be vacuous (it would pass even if D4 never flipped). The network-open and docker-absent abstain assertions are what prove the gate fails-closed.

**Replay-digest invariant (coordinate with sub-stream B):** add `test "result_digest is identical local vs docker (backend switch does not perturb replay)"` — run `ToolchainRunner.verification_result(ws, plan, backend: :local)` and `(..., backend: :docker, network: "none")` on the SAME reference workspace and assert the two `result_digest`s are EQUAL (they must be — the digest is computed before integrity_observations, `toolchain_runner.ex:103-108`). This locks the property that this sub-stream's backend switch is replay-safe.

**Re-calibration:** none (this is a test; it consumes the D4 calibration). It DOES serve as the live-path verification that the reference still auto-accepts after the flip.

**Green criteria:** `mix test test/conveyor/eval/integrity_discrimination_live_path_test.exs --seed 0` green WITH docker present (all 4–5 cases). The docker-absent case runs without docker (it injects unavailability) so it is green in CI too.

**Dependencies:** D1, D2, D3, D4. Last functional slice. Coordinate the replay-digest assertion with sub-stream B.

**Risks/traps:** (a) `RunSpec`/`RunAttempt` unique constraints — follow the existing docker test's fixture pattern (`create_artifact_run!` / unique labels) to avoid collisions. (b) The DataCase sandbox + `async: false` + docker build timeout (set `@moduletag timeout: 600_000` like the existing test). (c) Driving the full `serial_driver` is heavier than `RunGate.run_gate_only!` + `Finalizer.finalize!`; **recommendation: assert through `RunSlice.run!` (so the verify STATION selects docker — that is the wiring under test) then finalize via `Finalizer.finalize!(gate, %{... trust_evidence: TrustEvidence.from_run_output(result.output)}, ...)`.** Using `result.output` (not a hand-built map) is essential — a hand-built map would re-introduce the bypass the existing tests have and prove nothing new.

---

### Slice D7 — CI decision + scorecard wiring (the gate must be enforced, not just runnable)

**Goal:** Decide and implement how the hermetic gate participates in CI and the false-pass scorecard, so the milestone exit (decision 5: "zero false-pass on the FULL canary corpus in CI via `mix conveyor.eval.scorecard --gate`") is actually enforced.

**Findings driving the decision:**
- `.github/workflows/ci.yml` runs `MIX_ENV=test mix test` (line 74) — which INCLUDES `:eval` tests (only `live_agent` is excluded, `test/test_helper.exs:1`). **But the GitHub `ubuntu-latest` runner has NO docker daemon configured** in this workflow (no `services: docker` / no dind). So any `:eval` test that *requires* docker would either error or — via the D2 fallback — ABSTAIN.
- The scorecard gate (`mix conveyor.eval.scorecard --gate`, ci.yml:95) is DB-free and aggregates `eval/scorecards/inputs/*.json`; it blocks on `false_pass_rate > 0` etc. The hermetic discrimination tests do NOT currently emit scorecard inputs.

**The CI decision (RESOLVED IN-PLAN — Decision 10 is settled here, not deferred; concrete job spec below). Robert can override the job-structure choice, but the plan ships with a concrete, enforced docker CI job by default:**
1. **Make the D6 live-path test docker-OPTIONAL on the dockerless main job but docker-REQUIRED on the dedicated hermetic-gate job.** The D6 test's accept/network-open cases are `@tag :docker` and **skipped when `ToolchainRunner.docker_available?() == false`** (a `setup` that skips, mirroring how `:eval` is gated). The docker-ABSENT abstain case runs everywhere (it needs no docker; gated separately by the `hermetic_abstain_proof` $0 metric — see the dockerless-CI proof in D2/F7). This keeps the main `mix test` green on the dockerless main runner while the hermetic cases are FULLY exercised on the docker job.
2. **The docker-enabled CI job (CONCRETE SPEC — this is the resolution of Decision 10):**
   - **Job name:** `hermetic-gate` in `.github/workflows/ci.yml`.
   - **Runner:** `ubuntu-latest` — it has the docker daemon pre-installed on the host (`docker info` answers without a `services:` block or dind; the daemon is up by default on GitHub-hosted `ubuntu-latest`). No `services: docker` needed.
   - **Steps:** checkout → setup-beam (Elixir/OTP, matching the main job) → setup-python (for the sample venvs) → `MIX_ENV=test mix deps.get` → build the sample runner image(s) the D6 test needs (the `conveyor/beads-insight-runner:local` image, exactly as `integrity_discrimination_docker_test.exs` `ensure_image!` does) → **`MIX_ENV=test mix test --only docker --seed 0`** (runs the hermetic discrimination tests, including D6's live-path cases) → emit the hermetic scorecard input from that REAL docker run → **`MIX_ENV=test mix conveyor.eval.scorecard --gate`** restricted to / including the `hermetic_false_pass_rate` metric.
   - **Required-for-merge:** YES on the M4-exit PR (and ongoing). A skipped-everywhere hermetic test with no enforced metric is the exact "green because it ran nothing" vacuity this milestone exists to kill; the job being required-for-merge is what makes the hermeticity claim load-bearing. (Runner-up: fold docker into the existing main job — rejected because it slows the main job and couples unrelated failures.)
3. **Emit `hermetic_false_pass_rate` from a REAL docker run (blocking, target 0), NOT a static fixture.** A new `Mix.Tasks.Conveyor.Eval.Hermetic` task (or a DB-free emitter the D6 docker test invokes) writes `eval/scorecards/inputs/hermetic_discrimination.json` with `hermetic_false_pass_rate: 0` ONLY when, in the same real docker run: the docker-hermetic case ACCEPTED, the network-open case ABSTAINED, and the docker-absent case ABSTAINED. If any broken case auto-accepted, the metric is `> 0` and `--gate` exits non-zero. **Meta-assertion (mandatory anti-vacuity — "green because it ran nothing" must FAIL):** the emitter MUST assert the hermetic case set it ran was NON-EMPTY (`cases_run >= 3`) and record `cases_run` into the scorecard input; the scorecard `--gate` treats `cases_run == 0` (or the input absent) as UNHEALTHY/blocking, so a vacuously-empty hermetic run reddens CI rather than passing. Coordinate the metric key with the eval/scorecard owner so it fits `conveyor.eval_scorecard@1`.

**Where:** `.github/workflows/ci.yml` (new required `hermetic-gate` job, spec above), a new `Mix.Tasks.Conveyor.Eval.Hermetic` task OR an emitter inside the D6 docker test that writes the scorecard input (DB-free path preferred for the `--gate` step) and records `cases_run`. Tag plumbing in the D6 test.

**DISCRIMINATION TEST(S):** the scorecard-gate behavior is itself testable — `test/mix/tasks/conveyor_eval_scorecard_hermetic_test.exs`:
- **BROKEN case** — feed a synthetic input with `hermetic_false_pass_rate: 0.5` (a broken case auto-accepted) → `mix conveyor.eval.scorecard --gate` exits non-zero (`ExitCodes.fetch!(:canary_or_eval_false_negative)`). Proves the CI gate FAILS when a hermetic false-pass exists.
- **GOOD case** — input with `hermetic_false_pass_rate: 0.0` → exits zero.

> This is the anti-vacuity guard on the GATE ITSELF: prove the scorecard blocks on a planted hermetic false-pass, not just that it passes when clean.

**Re-calibration:** none.

**Green criteria:** `mix test test/mix/tasks/conveyor_eval_scorecard_hermetic_test.exs --seed 0` green; `mix conveyor.eval.scorecard --gate` exits 0 on the clean corpus and non-zero on a planted false-pass fixture; the new CI job is green on a docker-enabled runner.

**Dependencies:** D6 (the discrimination outcomes feed the metric). Coordinate the scorecard schema with the eval/scorecard-owning sub-stream.

**Risks/traps:** (a) **The deepest trap of the whole sub-stream:** if CI runs without docker AND the docker-requiring tests are simply SKIPPED AND no scorecard metric is emitted, then "zero false-pass in CI" is VACUOUSLY true — the gate is never exercised. The mitigation is mandatory: the docker-enabled CI job MUST run the discrimination test on the milestone-exit branch, AND the scorecard metric MUST be emitted by a real run (not a static fixture). A skipped-everywhere hermetic test is exactly the "looks-wired-but-vacuous" failure mode this program exists to prevent — call it out in the PR. (b) Decide whether the docker job is required-for-merge or informational; recommendation: required-for-merge for the M4-exit PR, then required ongoing. (c) The external-buggy-commit catch-rate falsifier probe (decision 5) is a SEPARATE, post-activation falsifier — note that it belongs to the milestone-exit checklist, not to D7's CI wiring, but D7's scorecard metric is its home when it runs.

---

### Cross-cutting risks / looks-wired-but-vacuous traps (carry-forward + new)

1. **(Seed, load-bearing) The laundering trap:** `trust_evidence.ex:56` `integrity(_) -> "trustworthy"`. Adding docker WITHOUT D4 is pure ceremony — the non-hermetic run still auto-accepts. D4 is the real deliverable; D3 is its enabler. Never ship D3 as "the hermetic gate" without D4.
2. **(New) The skipped-test vacuity (D7):** a docker-gated discrimination test that is skipped in CI and emits no enforced metric makes "zero false-pass in CI" vacuously true. The scorecard metric + a docker-enabled job are mandatory, not optional.
3. **(New) The docker-error vs docker-absent confusion (D3):** an *erroring* docker run (missing image, dead daemon mid-run) is worse than an *absent* one — it can crash the gate or hang. `docker_available?` (D1, hardened) + image-existence awareness must route to the ABSTAIN path, not an exception.
4. **(New) The hand-built-context bypass (D6):** the existing docker/live tests prove the COMPONENTS discriminate but bypass the assembler/stations. A new test that also hand-builds the gate context proves nothing new. D6 MUST drive `RunSpecAssembler` + `RunSlice` + the real `result.output`.
5. **(Seed, coordinate B) Replay-digest ordering:** `toolchain_runner.ex:103-108` computes `result_digest` before attaching integrity_observations. PRESERVED by construction (we only change opts), and LOCKED by the D6 local-vs-docker digest-equality assertion.
6. **(New) The default-flag cop-out (D3):** `hermetic_gate: false` default is acceptable ONLY because D4 makes `:local`/`not_assessed` abstain regardless — the flag chooses *whether to attempt docker*, never *whether a non-hermetic result can accept*. If anyone later reads `hermetic_gate: false` as "skip hermeticity, auto-accept," that re-opens the hole. Document the invariant: post-D4, a non-hermetic run can NEVER auto-accept, flag or no flag.
7. **(New) Whole-suite triage on the flip (D4):** flipping the laundering may red unrelated tests that silently depended on no-integrity-signal accepting. Triage each — update to docker OR fix a real second vacuity — never blanket-green them (that re-launders the vacuity in the test layer).
8. **(Seed) gx has no `reference_full.patch`** (only per-slice patches) — the gx leg of any "reference auto-accepts" check must use a per-slice reference patch + per-slice test_refs, not a full-build patch. beads_insight has `reference_full.patch`. Account for this when extending the discrimination corpus to gx.
9. **(New) Per-project runner image is out of scope** — D3 threads an explicit `docker_image` opt (default pinned ghcr image); a `Project.runner_image` registry is a follow-on. For beads_insight/gx the D6 test builds the local image. Flag: production conductor must ensure the image exists before a hermetic run, else it errors.

---

## Sub-stream G — Data-integrity fixes (dr1m.1.2, dr1m.8) [key: `G-data-integrity`]

> **Role in M4:** This is the **ride-along appendix**, not a blocking sub-stream. Neither fix changes a single gate **verdict** — they fix *bookkeeping* (duplicate provenance edges; a migration that is unsafe on a populated DB). They are sequenced **last** and depend on nothing; the live-signal work (`G-trust-producers`, `G-abstain`, `G-hermetic`, `G-gate-stages`, `G-mutant-gauntlet`) does **not** wait on them and they do **not** touch any TrustScore weight or threshold. They exist because Robert ratified MAXIMAL scope (decision 1: "PLUS the data-integrity fixes (dr1m.1.2, dr1m.8)"). Land them as the final two green commits of M4.
>
> **Why they still matter (truth over optimism):**
> - **dr1m.1.2** is genuinely load-bearing for the *Genome*. Once M4 makes the loop run real plans (and re-runs / replays / retries them), every re-finalization of the same slice/attempt today mints a fresh batch of logically-identical `CodeProvenanceEdge` rows with **different** `edge_sha256`s. The sole dedup identity never fires, so the provenance graph silently accumulates duplicates. Any downstream that counts edges, dedupes by `edge_sha256`, or trusts "one edge per (slice, symbol, criterion, decision)" is wrong. This is a correctness bug in the very substrate M4 is supposed to make trustworthy.
> - **dr1m.8** is currently **latent**: the bad `up`/`down` only bite on a **populated, non-Sandbox** DB, and CI runs everything under `Ecto.Adapters.SQL.Sandbox` (`config/test.exs:14`), so green test runs *never* surface it. **But** there is a real durable `conveyor_dev` DB (`config/dev.exs`: `pool_size: 10`, real Postgres, not Sandbox) and a `Conveyor.Repo` block in `config/runtime.exs` (prod path). The moment anyone runs `mix ecto.migrate` against a dev/prod DB that already has artifact rows, or tries to roll back, the migration can fail. So the fix is worth shipping, but its **urgency is conditional** — see the "Is a durable DB even planned before M4 ships?" decision below.

### Verification of seed facts (done before designing — all CONFIRMED)

I Read the named modules at the named lines. Every seed fact is accurate:

| Seed claim | Verified at | Status |
|---|---|---|
| `edge_sha256 = CanonicalJson.digest(attrs)` over the full attrs map | `lib/conveyor/genome/back_edge.ex:69` | ✅ confirmed |
| `attrs` includes `gate_result_id` | `back_edge.ex:44` | ✅ confirmed |
| `attrs` includes `run_attempt_id` | `back_edge.ex:42` | ✅ confirmed |
| sole dedup is `identity :unique_edge_sha256, [:edge_sha256]` | `lib/conveyor/factory/code_provenance_edge.ex:78` | ✅ confirmed (no upsert anywhere) |
| Finalizer mints a FRESH `GateResult` per finalization (no upsert) | `lib/conveyor/gate/finalizer.ex:105` (`Ash.create!(GateResult, ...)`), edges minted at `finalizer.ex:87` via `BackEdge.mint!` | ✅ confirmed |
| migration `up` creates two unique indexes with NO dedupe | `priv/repo/migrations/20260620110000_update_artifact_projection_identity.exs:11-19` | ✅ confirmed |
| migration `up` demotes `(sha256,size_bytes)` to non-unique | same file `:5-9` | ✅ confirmed |
| migration `down` recreates the OLD unique `(sha256,size_bytes)` index with no dedupe | same file `:35-37` | ✅ confirmed |
| Artifact resource now keys identity on `projection_path` | `lib/conveyor/factory/artifact.ex:57-60` (`unique_run_attempt_projection_path`, `unique_station_run_projection_path`) | ✅ confirmed |
| project runs Sandbox in test | `config/test.exs:14` (`pool: Ecto.Adapters.SQL.Sandbox`) | ✅ confirmed |

**HAZARD CHECK — "is `edge_sha256` composition pinned by any TrustBundle/replay/digest test?" — CONFIRMED CLEAR (this is the make-or-break check for dr1m.1.2):**
I grepped every `*.exs` under `test/` for `edge_sha256`. The **only** occurrences are in `test/conveyor/trust_bundle_test.exs:14` and `:29`, and both use a **literal** `digest("edge-1")` string passed directly into `TrustBundle.build/1` — they never mint a real edge through `BackEdge`, so they do **not** pin the digest *composition*. `test/conveyor/gate_finalizer_test.exs:108-114` asserts edge **fields** (`code_symbol`, `acceptance_criterion_id`, `role`, `decision`, `patch_sha256`, `gate_result_id`) but **never** asserts the `edge_sha256` value. The replay tests (`test/conveyor/replay_test.exs`, `test/mix/tasks/conveyor_replay_test.exs`) contain zero references to `edge_sha256` / `CodeProvenanceEdge` / `provenance_edge`. **Conclusion: changing the digest composition breaks no existing assertion.** The change is safe to make.

**Additional verified facts that shape the design:**
- `CanonicalJson.encode/1` (`lib/conveyor/canonical_json.ex:13-21`) **sorts object keys recursively**, so `digest(map)` is independent of key insertion order. Dropping two keys from the digest input is therefore deterministic and stable.
- The artifact-identity migration `20260620110000` is **NOT the latest** migration — `20260620200000_add_abstained_run_attempt_outcome.exs` and `20260620210000_add_gate_result_trust_score.exs` come after it. **Therefore the artifact migration may already be applied to a dev/prod DB and MUST NOT be edited in place** (editing an applied migration is a cardinal sin — it desyncs `schema_migrations`). dr1m.8's fix must be a **new forward-only migration**, OR the original may only be edited if we can guarantee it's never been applied anywhere (we cannot guarantee that). The design below uses a new forward-only migration. (This is a correction/refinement of the seed-fact phrasing, which implied editing `up`/`down` of the original.)
- `Conveyor.FactoryFixtures.create_artifact_run!/1` (`test/support/factory_fixtures.ex:15-121`) is the canonical fixture: it creates project→plan→epic→slice→run_spec→run_attempt→station_run→artifact, and `gate_finalizer_test.exs` already uses it. The dr1m.1.2 discrimination test reuses it directly.

---

### Slice G1 — Dedup `CodeProvenanceEdge` on the logical tuple (dr1m.1.2)

**Goal:** Make re-finalizing the same slice/attempt mint **zero** duplicate provenance edges, by hashing only the *logical* identity of an edge (not the per-finalization nonces) and upserting on `edge_sha256`.

**Closes:** `dr1m.1.2`.

**Depends on:** nothing. Orders **before** G2 within this sub-stream (arbitrary; they're independent, but G1 is the higher-leverage one so do it first). No dependency on any other M4 sub-stream. Other sub-streams do NOT depend on this.

#### The bug, precisely

`Conveyor.Genome.BackEdge.create_edge!/1` (`back_edge.ex:60-72`) builds an `attrs` map that includes:
- `run_attempt_id` (`:42`) — same across re-runs of an attempt, but a *new attempt* is a new id (logically a different attempt, fine to keep in the digest... **but see decision below**),
- `gate_result_id` (`:44`) — a **fresh nonce on every finalization** (`finalizer.ex:105` creates a new `GateResult` with `Ash.create!`, no upsert),

then computes `edge_sha256 = CanonicalJson.digest(attrs)` over the **whole map including those two ids** (`:69`). The sole dedup is `identity :unique_edge_sha256, [:edge_sha256]` (`code_provenance_edge.ex:78`). Because `gate_result_id` changes every finalization, the digest changes every finalization, the unique constraint never matches a prior row, and `Ash.create!` happily inserts a logically-identical edge. Re-run / retry / replay → duplicates accumulate without bound.

#### Decision: which fields are "the logical tuple"?

The seed fact proposes hashing over: `(slice_id, code_symbol, claim_pointer, acceptance_criterion_id, decision, patch_sha256, contract_lock_sha256, claim_set_digest, schema_version, role)` and **dropping `gate_result_id` + `run_attempt_id`** from the digest (keeping both as stored columns).

**I agree, with one deliberate, flagged sub-decision (baked, overridable by Robert):**

- **Drop `gate_result_id` from the digest — non-negotiable.** It is a pure per-finalization nonce; keeping it is the entire bug.
- **Drop `run_attempt_id` from the digest too — recommended, and here's the reasoning + the tradeoff.** The provenance edge means "this code symbol satisfies this acceptance criterion under this patch + contract-lock + claim-set, as verified by a passing gate." That meaning is fully captured by `(slice_id, code_symbol, claim_pointer, acceptance_criterion_id, decision, patch_sha256, contract_lock_sha256, claim_set_digest, schema_version, role)`. Two **different attempts** that land the **exact same `patch_sha256` + `contract_lock_sha256` + `claim_set_digest`** are, by content-address, producing the *same verified fact* — deduping them is correct, not lossy (the differing attempt id is recorded in the stored `run_attempt_id` column for forensics, and the gate result is reachable via `gate_result_id` column). Conversely, a genuinely different patch produces a different `patch_sha256`, which still yields a different digest. So including `run_attempt_id` in the digest would **defeat** dedup across re-runs that reproduce the same artifact — exactly the duplicate-accumulation we're trying to kill. **Tradeoff / runner-up:** if you keep `run_attempt_id` in the digest, you still kill the *re-finalization-of-the-same-attempt* duplicates (the dominant case) but you reintroduce duplicates whenever a **retry produces a byte-identical patch** (common with deterministic agents/replay). I judge that case important enough — replay and deterministic re-runs are core to Conveyor — to drop `run_attempt_id`. **If Robert wants attempt-scoped edges (one edge row per attempt, even for identical patches), keep `run_attempt_id` in the digest; the slice's discrimination test must then be adjusted to re-finalize the *same* gate-attempt rather than create a new attempt.**

The chosen logical tuple (10 fields):
```
slice_id, code_symbol, claim_pointer, acceptance_criterion_id,
decision, patch_sha256, contract_lock_sha256, claim_set_digest,
schema_version, role
```
Note: `claim_origin` and `invalidation_policy` are **excluded** from the digest. `invalidation_policy` is a constant policy tag (`"invalidate_on_change"`), not part of the edge's logical identity. `claim_origin` is derived from the claim and is already reflected in `claim_set_digest`; including it risks digest churn if claim-origin labeling changes without the claim changing. (Baked decision — if Robert wants `claim_origin` in the digest, add it; it's harmless either way since it's stable for a given claim set, but excluding it is cleaner.)

#### Files + functions to change

**1. `lib/conveyor/genome/back_edge.ex` — `create_edge!/1` (`:60-72`)**

CURRENT (`:67-71`):
```elixir
Ash.create!(
  CodeProvenanceEdge,
  Map.put(attrs, :edge_sha256, Conveyor.CanonicalJson.digest(attrs)),
  domain: Factory
)
```
The digest is taken over the **full** `attrs` (which at this point already has `schema_version`/`role`/`invalidation_policy` merged in at `:61-65`, and still carries `run_attempt_id`/`gate_result_id` from the caller at `back_edge.ex:42`/`:44`).

TARGET:
```elixir
defp create_edge!(attrs) do
  attrs =
    attrs
    |> Map.put(:schema_version, @schema_version)
    |> Map.put(:role, @role)
    |> Map.put(:invalidation_policy, @invalidation_policy)

  edge_sha256 = Conveyor.CanonicalJson.digest(logical_identity(attrs))

  Ash.create!(
    CodeProvenanceEdge,
    Map.put(attrs, :edge_sha256, edge_sha256),
    domain: Factory,
    upsert?: true,
    upsert_identity: :unique_edge_sha256
  )
end

# dr1m.1.2: the edge digest hashes ONLY the logical identity of the verified
# fact — never the per-finalization nonces (`gate_result_id`) or the attempt id.
# Two finalizations (or two attempts producing the same patch) thus collapse to
# one edge instead of accumulating duplicates. The nonces are still STORED on the
# row (Map columns) for forensics; they are just kept out of the IDENTITY hash.
@edge_logical_keys [
  :slice_id,
  :code_symbol,
  :claim_pointer,
  :acceptance_criterion_id,
  :decision,
  :patch_sha256,
  :contract_lock_sha256,
  :claim_set_digest,
  :schema_version,
  :role
]

defp logical_identity(attrs) do
  attrs
  |> Map.take(@edge_logical_keys)
  |> Map.new(fn {k, v} -> {Atom.to_string(k), normalize_digest_value(v)} end)
end

# `decision` arrives as an atom (`:passed`); CanonicalJson encodes atoms as their
# string form already, but normalizing here makes the digest input explicit and
# stable regardless of whether a caller passes the atom or its string.
defp normalize_digest_value(value) when is_atom(value) and not is_nil(value),
  do: Atom.to_string(value)

defp normalize_digest_value(value), do: value
```

Notes for the executor:
- The `Map.new(... {Atom.to_string(k), ...})` keying is belt-and-suspenders: `CanonicalJson.encode/1` already does `to_string(key)` and sorts, so atom-keyed and string-keyed maps already digest identically. Stringifying here just makes the digest input visually explicit and immune to any future `CanonicalJson` change. **Do not** skip `Map.take` — taking only the 10 logical keys is the whole fix.
- `upsert?: true` + `upsert_identity: :unique_edge_sha256` makes a re-mint a **no-op upsert** instead of a `Ash.Error.Invalid` unique-constraint raise. This is the seed's "optionally upsert on the identity" — I make it **required**, not optional, because without it a re-mint would now *raise* (the digest finally collides) and crash finalization. Confirm `CodeProvenanceEdge`'s `create: :*` action (`code_provenance_edge.ex:17`) supports upsert — it does; Ash's default create action accepts `upsert?`/`upsert_identity` opts. If Ash complains that the action needs an explicit `upsert?` flag, add a named create action `create :mint do upsert? true; upsert_identity :unique_edge_sha256; accept :* end` and call it via `Ash.create!(CodeProvenanceEdge, attrs, action: :mint, domain: Factory)`. (Verify which form your Ash version accepts during implementation; both are standard.)

**2. `lib/conveyor/factory/code_provenance_edge.ex` — identity (`:77-79`)**

No schema change strictly required (the `:unique_edge_sha256` identity already exists and is the upsert target). **Do NOT** widen the identity to the 10 logical columns — the digest *is* the identity, and a single `[:edge_sha256]` unique index is correct and cheaper. Leave `:77-79` unchanged. (If you ever wanted a defense-in-depth DB constraint on the logical tuple, that's a separate, larger change with its own migration; out of scope here.)

#### The discrimination test (anti-vacuity is the point)

**Test file:** `test/conveyor/back_edge_dedup_test.exs` (new). Use `Conveyor.DataCase, async: false` (mirrors `gate_finalizer_test.exs`).

```elixir
defmodule Conveyor.BackEdgeDedupTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.CodeProvenanceEdge
  alias Conveyor.Factory.GateResult
  alias Conveyor.Genome.BackEdge

  setup do
    fixture = create_artifact_run!(blob_root: temp_dir!("back-edge-dedup"))
    %{run_attempt: fixture.run_attempt, slice_id: fixture.run_attempt.slice_id}
  end

  defp mint_context(ctx) do
    %{
      run_attempt: ctx.run_attempt,
      run_attempt_id: ctx.run_attempt.id,
      contract_lock_sha256: "sha256:contract",
      patch_sha256: "sha256:patch",
      code_symbols: ["Conveyor.Tasks.complete/1"],
      acceptance_criteria: [
        %{"id" => "AC-1", "text" => "t", "requirement_refs" => ["REQ-1"]}
      ],
      claims_by_pointer: %{
        "/acceptance_criteria/0" => %{origin: :deterministic, source_anchor_refs: ["REQ-1"]}
      }
    }
  end

  defp fresh_gate_result! do
    Ash.create!(
      GateResult,
      %{level: :slice, passed: true, stages: [], gate_version: "g@1"},
      domain: Factory
    )
  end

  # GOOD-signal case: a single finalization mints exactly one edge → ACCEPT.
  test "minting once creates exactly one provenance edge" do
    ctx = mint_context(%{run_attempt: ctx_run_attempt()})
    [edge] = BackEdge.mint!(ctx, fresh_gate_result!())
    assert edge.code_symbol == "Conveyor.Tasks.complete/1"
    assert length(Ash.read!(CodeProvenanceEdge, domain: Factory)) == 1
  end

  # BROKEN-signal case (the duplicate-on-re-finalization bug): re-minting on a
  # SECOND, distinct gate_result for the SAME slice/attempt/patch must produce
  # NO new row. Before the fix this asserts == 1 and FAILS with 2 (proving the
  # gate against duplicates actually catches the regression).
  test "re-minting on a second gate_result for the same slice/attempt creates NO duplicate edge" do
    ctx = mint_context(%{run_attempt: ctx_run_attempt()})

    [edge1] = BackEdge.mint!(ctx, fresh_gate_result!())
    [edge2] = BackEdge.mint!(ctx, fresh_gate_result!())

    # Same logical fact ⇒ identical digest ⇒ upsert ⇒ same row, no duplicate.
    assert edge1.edge_sha256 == edge2.edge_sha256
    assert length(Ash.read!(CodeProvenanceEdge, domain: Factory)) == 1
  end

  # NEGATIVE control: a genuinely DIFFERENT patch is a DIFFERENT fact ⇒ a new edge.
  # This proves the dedup is not over-broad (it does not collapse distinct facts).
  test "a different patch_sha256 mints a distinct edge (dedup is not over-broad)" do
    ctx_a = mint_context(%{run_attempt: ctx_run_attempt()})
    ctx_b = Map.put(ctx_a, :patch_sha256, "sha256:patch-DIFFERENT")

    [_a] = BackEdge.mint!(ctx_a, fresh_gate_result!())
    [_b] = BackEdge.mint!(ctx_b, fresh_gate_result!())

    assert length(Ash.read!(CodeProvenanceEdge, domain: Factory)) == 2
  end
end
```
> Executor note: the `ctx_run_attempt()` placeholder above must be replaced with the `run_attempt` captured in `setup` (thread it through `context`, e.g. `setup` returns `%{run_attempt: ...}` and each test takes `ctx` and calls `mint_context(ctx)`). The three tests above show the *shape*; wire the `setup` context in cleanly. The `GateResult` create attrs (`level`, `passed`, `stages`, `gate_version`) must match the resource's required fields — cross-check against `lib/conveyor/factory/gate_result.ex` when writing (the finalizer builds them at `finalizer.ex:97-105`; reuse that attr set if `gate_version`/`gate_code_sha256` etc. are required).

**Anti-vacuity proof:** the BROKEN-signal test (`re-minting ... creates NO duplicate edge`) is written to **fail on `main` as it stands today** — without the digest change, the second `mint!` produces a row with a *different* `edge_sha256` and `length(...) == 2`, so `assert ... == 1` fails. Run it against the unpatched code FIRST to confirm it goes red (`mix test test/conveyor/back_edge_dedup_test.exs:<line> --seed 0` should show 1 failure), THEN apply the fix and confirm green. That red→green is the evidence the gate actually catches the duplicate bug. The NEGATIVE control proves we didn't "fix" it by collapsing everything to one row.

#### Re-calibration

**None.** This slice touches **no** TrustScore weight or threshold and changes **no** verdict. The `gate_finalizer_test.exs` known-good references (`"...high trust evidence still auto-accepts"` at `:213` and the beads_insight/gx reference corpus) are unaffected — they assert *one* edge per single finalization, which still holds. No re-tune needed.

#### Green criteria
- `mix test --exclude eval --seed 0` is fully green, including the new `back_edge_dedup_test.exs`.
- `gate_finalizer_test.exs` still green (it asserts `[edge] = Ash.read!(CodeProvenanceEdge, ...)` for a single finalization at `:108` — one edge, unchanged).
- No `:eval` test or scorecard change expected; `mix conveyor.eval.scorecard --gate` verdict counts are byte-identical before/after (this slice does not alter any verdict). Run it once to confirm zero drift.

#### Risks / traps
- **Looks-wired-but-vacuous trap (the central one):** a test that only does `mint!` once and asserts one edge **proves nothing** about dedup — it passes on the buggy code too. The discrimination test MUST re-mint on a *second distinct gate_result* and assert the count stays 1. (Covered above; do not delete that test.)
- **Upsert-vs-raise trap:** once the digest is logical, a naive `Ash.create!` (no upsert) would now **raise** on the second mint (the unique constraint finally fires). If you change the digest but forget `upsert?: true`, finalization crashes on every re-run. Both halves of the fix are required together.
- **Over-broad dedup trap:** if you accidentally drop `patch_sha256` or `claim_set_digest` from the logical tuple, two *different* code states collapse to one edge — a silent provenance loss that's worse than duplicates. The NEGATIVE-control test guards this; keep it.
- **`decision` atom-vs-string trap:** `decision: :passed` is an atom in `attrs` (`back_edge.ex:49`). `CanonicalJson` already stringifies atoms, but the explicit `normalize_digest_value/1` makes the digest input unambiguous. Don't remove it.
- **GateResult create-attrs drift:** the test's `fresh_gate_result!/0` must satisfy `GateResult`'s required attributes. If `gate_result.ex` requires more than `level/passed/stages`, the test setup will raise at create time, not at the assertion. Cross-check before finalizing the test.

---

### Slice G2 — Make the artifact-projection-identity migration dedup-safe & reversible (dr1m.8)

**Goal:** Ensure that applying the artifact-projection unique indexes against a **populated** DB pre-dedupes (keeping the latest row) instead of failing, and that the migration has an honest, dedupe-safe `down` — OR is explicitly marked irreversible with a documented rationale. Add a real test that exercises the dedupe on populated data.

**Closes:** `dr1m.8`.

**Depends on:** nothing. Orders **after** G1 within this sub-stream (independent; arbitrary order). No cross-sub-stream dependency.

#### The bug, precisely

`priv/repo/migrations/20260620110000_update_artifact_projection_identity.exs`:
- **`up` (`:5-19`)** demotes `(sha256, size_bytes)` from unique to a plain index (`:5-9`) and then creates `unique_index(:artifacts, [:run_attempt_id, :projection_path], where: "run_attempt_id IS NOT NULL")` (`:11-14`) and `unique_index(:artifacts, [:station_run_id, :projection_path], where: "station_run_id IS NOT NULL")` (`:16-19`) — **with no dedupe step**. If the table already has two rows sharing the same `(run_attempt_id, projection_path)` (which was *possible* under the old `(sha256,size_bytes)`-only identity — two different blobs at the same projection path for the same attempt), `CREATE UNIQUE INDEX` **fails** with a duplicate-key error and the migration aborts.
- **`down` (`:22-38`)** drops the new indexes and recreates `unique_index(:artifacts, [:sha256, :size_bytes])` (`:35-37`) — **with no dedupe**. But `up` allowed duplicate `(sha256, size_bytes)` rows to exist (it demoted that index to non-unique and the resource now keys on `projection_path`, `artifact.ex:57-60`). So `down` can **fail** to re-create the unique index because populated data now violates it. The rollback is a trap.

**Clean on an EMPTY db** (no rows → no violations). **Dangerous only on a POPULATED non-test db.** Test runs use `Ecto.Adapters.SQL.Sandbox` (`config/test.exs:14`) and start empty, so CI never surfaces this.

#### Critical constraint discovered during verification — DO NOT edit the original migration in place

`20260620110000` is **not the latest** migration (`20260620200000` and `20260620210000` come after it). It may **already be applied** to a dev (`conveyor_dev`) or prod DB. **Editing an applied migration's `up`/`down` desyncs `schema_migrations` and is forbidden.** Therefore dr1m.8's fix is delivered as a **NEW forward-only migration** that:
1. pre-dedupes any existing `(run_attempt_id, projection_path)` / `(station_run_id, projection_path)` duplicates (keeping the latest row), then
2. (idempotently) ensures the two partial unique indexes exist (re-create if missing — they may already exist from `20260620110000` on an empty DB), and
3. pre-dedupes `(sha256, size_bytes)` and provides a dedupe-safe `down`.

This is the correct, safe shape regardless of whether `20260620110000` was ever applied.

#### Decision: fix-forward migration vs. mark-irreversible — and the gating question

**The gating question (open for Robert): is a durable, populated, non-Sandbox `Conveyor.Repo` DB actually in scope before M4 ships?**
- If **NO** (Conveyor stays Sandbox/ephemeral for all of M4 — every run starts from a fresh DB, dev DB is disposable, no rollback-on-populated-data scenario exists), then dr1m.8 is a **non-issue in practice** and the cheapest honest fix is to **mark the original migration's intent in a docstring and add a dedupe-safe forward migration anyway** (so it's correct *if/when* a durable DB appears) but treat it as **deferrable** — it can ship as the very last commit or be parked. **Recommended in this case: still ship the forward migration (it's ~30 lines and removes a latent footgun), but flag in the M4 handoff that it's belt-and-suspenders, not load-bearing.**
- If **YES** (a durable run-history DB is planned — and the existence of `config/dev.exs` with `pool_size: 10` and `config/runtime.exs` Repo block suggests it's at least anticipated), then dr1m.8 is **load-bearing** and the forward migration + dedupe-safe `down` must ship and be tested against populated data.

**My recommendation (baked, overridable):** Ship the forward-only dedupe-safe migration **with a real dedupe `down`** (option below), gated behind the test. It's cheap, it's correct either way, and it removes a real footgun the moment a durable DB exists. Do **not** choose "mark irreversible" unless Robert explicitly says durable DB is out of scope AND we want to minimize migration surface — irreversibility is a worse default because it makes any future rollback impossible. **Reasoning:** the complexity cost of a correct `down` here is ~10 lines; the cost of irreversibility is a permanent one-way door. Per HUMAN.md's brake-on-complexity, ~10 lines for reversibility is well worth it.

#### Files to create

**New migration: `priv/repo/migrations/20260622120000_dedupe_safe_artifact_projection_identity.exs`** (timestamp must sort AFTER `20260620210000`; bump to "now" — `20260622120000` is fine for 2026-06-22).

```elixir
defmodule Conveyor.Repo.Migrations.DedupeSafeArtifactProjectionIdentity do
  @moduledoc """
  dr1m.8: makes the artifact-projection unique-index migration safe on a POPULATED
  database. The original `20260620110000` created two partial UNIQUE indexes with no
  dedupe step, so applying it to a table that already held duplicate
  (run_attempt_id, projection_path) / (station_run_id, projection_path) rows aborted.
  Its `down` likewise recreated the legacy unique (sha256, size_bytes) index without
  dedupe and could fail. We never edit an applied migration in place; this forward
  migration pre-dedupes (keeping the LATEST row by created_at, tie-broken by id) and
  then idempotently (re)creates the unique indexes.
  """
  use Ecto.Migration

  def up do
    # Pre-dedupe (run_attempt_id, projection_path): keep the newest row per key.
    execute("""
    DELETE FROM artifacts a
    USING artifacts b
    WHERE a.run_attempt_id IS NOT NULL
      AND a.run_attempt_id = b.run_attempt_id
      AND a.projection_path = b.projection_path
      AND (a.created_at, a.id) < (b.created_at, b.id);
    """)

    # Pre-dedupe (station_run_id, projection_path): keep the newest row per key.
    execute("""
    DELETE FROM artifacts a
    USING artifacts b
    WHERE a.station_run_id IS NOT NULL
      AND a.station_run_id = b.station_run_id
      AND a.projection_path = b.projection_path
      AND (a.created_at, a.id) < (b.created_at, b.id);
    """)

    # Idempotently ensure the partial unique indexes exist (they may already exist
    # from 20260620110000 on an empty DB; drop_if_exists + create is safe either way).
    drop_if_exists unique_index(:artifacts, [:run_attempt_id, :projection_path],
                     name: :artifacts_unique_run_attempt_projection_path_index
                   )

    create unique_index(:artifacts, [:run_attempt_id, :projection_path],
             name: :artifacts_unique_run_attempt_projection_path_index,
             where: "run_attempt_id IS NOT NULL"
           )

    drop_if_exists unique_index(:artifacts, [:station_run_id, :projection_path],
                     name: :artifacts_unique_station_run_projection_path_index
                   )

    create unique_index(:artifacts, [:station_run_id, :projection_path],
             name: :artifacts_unique_station_run_projection_path_index,
             where: "station_run_id IS NOT NULL"
           )
  end

  def down do
    # Dedupe-safe reversal: the legacy identity was unique (sha256, size_bytes).
    # Pre-dedupe before recreating that unique index so rollback cannot fail on
    # rows that became duplicate-by-(sha256,size_bytes) while the projection-path
    # identity was in force.
    execute("""
    DELETE FROM artifacts a
    USING artifacts b
    WHERE a.sha256 = b.sha256
      AND a.size_bytes = b.size_bytes
      AND (a.created_at, a.id) < (b.created_at, b.id);
    """)

    drop_if_exists unique_index(:artifacts, [:run_attempt_id, :projection_path],
                     name: :artifacts_unique_run_attempt_projection_path_index
                   )

    drop_if_exists unique_index(:artifacts, [:station_run_id, :projection_path],
                     name: :artifacts_unique_station_run_projection_path_index
                   )

    drop_if_exists index(:artifacts, [:sha256, :size_bytes],
                     name: :artifacts_sha256_size_bytes_index
                   )

    create unique_index(:artifacts, [:sha256, :size_bytes],
             name: :artifacts_unique_sha256_size_bytes_index
           )
  end
end
```

Executor notes:
- **Verify the `created_at` column name** before writing the SQL. `artifact.ex:42` declares `create_timestamp :created_at`, so the physical column is `created_at`. Confirm with `\d artifacts` or by reading the create-table migration if unsure. If it's `inserted_at` in some environments, adjust.
- The `(a.created_at, a.id) < (b.created_at, b.id)` row-comparison "keep newest" idiom deletes every row that is strictly older (tie-broken by id) than another row sharing the key — leaving exactly one (the max) per key. This is the standard safe dedupe.
- `down`'s `DELETE` is a **data-destroying** rollback (it drops artifact rows to satisfy the old unique constraint). That is inherent to reversing an identity-narrowing migration on populated data; the docstring must say so. This is acceptable for a rollback (rollbacks are recovery operations), but call it out.
- **DO NOT** touch `20260620110000_update_artifact_projection_identity.exs`. Leave it byte-for-byte as-is (it's correct on empty DBs and may be applied). The only thing you may add to it is a one-line `@moduledoc` pointer to the new migration — and only if you're certain it hasn't been applied anywhere; safest is to leave it completely untouched and put the cross-reference solely in the new migration's docstring.

#### The discrimination test (anti-vacuity)

The hard part: tests run under Sandbox, which **starts empty**, so a naive test never has duplicate rows to dedupe and proves nothing. To make this test *discriminating*, it must **manufacture the populated-with-duplicates precondition** and then prove the dedupe SQL collapses it.

**Test file:** `test/conveyor/factory/artifact_projection_dedupe_test.exs` (new). `use Conveyor.DataCase, async: false`.

Strategy: insert two artifact rows that share `(run_attempt_id, projection_path)` **before** the unique index exists, then run the dedupe SQL (the migration's `up` body, or the SQL directly via `Conveyor.Repo.query!`) inside the test, and assert exactly one survives — and that it's the **newest**. Because the unique index from `20260620110000` is already present in the test schema, you can't insert the duplicate through the normal Ash path (it'd be rejected). Two honest options:

- **Option A (recommended): test the dedupe SQL in isolation against a temp table.** Create a scratch table mirroring the relevant columns, seed duplicates, run the exact `DELETE ... USING ...` statement, assert one survivor. This proves the *dedupe logic* is correct (the load-bearing, novel part of the fix) without fighting the live unique index. It's fully deterministic and `$0`.
- **Option B (stronger but heavier): drop the unique index inside the test, insert duplicates via raw `Repo.query!`, run the migration's `up`, assert it (a) does not raise and (b) leaves one row.** This exercises the real migration body end-to-end but mutates schema mid-test; under Sandbox the transaction rollback restores it. Use `Ecto.Adapters.SQL.Sandbox` checkout semantics carefully.

**Recommended: Option A** (deterministic, cheap, proves the novel logic), with a one-line comment pointing at Option B as the heavier end-to-end variant if Robert wants migration-body coverage.

```elixir
defmodule Conveyor.Factory.ArtifactProjectionDedupeTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Repo

  @dedupe_sql """
  DELETE FROM artifact_dedupe_scratch a
  USING artifact_dedupe_scratch b
  WHERE a.run_attempt_id = b.run_attempt_id
    AND a.projection_path = b.projection_path
    AND (a.created_at, a.id) < (b.created_at, b.id);
  """

  setup do
    Repo.query!("""
    CREATE TEMP TABLE artifact_dedupe_scratch (
      id uuid PRIMARY KEY,
      run_attempt_id uuid,
      projection_path text,
      created_at timestamptz
    ) ON COMMIT DROP;
    """)

    :ok
  end

  defp insert!(id, attempt, path, ts) do
    Repo.query!(
      "INSERT INTO artifact_dedupe_scratch (id, run_attempt_id, projection_path, created_at) VALUES ($1,$2,$3,$4)",
      [Ecto.UUID.dump!(id), Ecto.UUID.dump!(attempt), path, ts]
    )
  end

  # GOOD: no duplicates → dedupe is a no-op, both distinct rows survive.
  test "dedupe leaves distinct (attempt, path) rows untouched" do
    a = Ecto.UUID.generate()
    insert!(Ecto.UUID.generate(), a, "evidence.json", ~U[2026-06-22 00:00:00Z])
    insert!(Ecto.UUID.generate(), a, "OTHER.json",    ~U[2026-06-22 00:00:01Z])

    Repo.query!(@dedupe_sql)

    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM artifact_dedupe_scratch")
    assert count == 2
  end

  # BROKEN-signal precondition: two rows share (attempt, path). Without the dedupe
  # the later CREATE UNIQUE INDEX would ABORT. The dedupe must collapse to ONE row,
  # and it must keep the NEWEST (so re-projection wins). This test FAILS (count==2)
  # if the dedupe SQL is wrong/absent — proving the fix actually de-duplicates.
  test "dedupe collapses duplicate (attempt, path) to the single newest row" do
    a = Ecto.UUID.generate()
    older = Ecto.UUID.generate()
    newer = Ecto.UUID.generate()

    insert!(older, a, "evidence.json", ~U[2026-06-22 00:00:00Z])
    insert!(newer, a, "evidence.json", ~U[2026-06-22 00:00:05Z])

    Repo.query!(@dedupe_sql)

    %{rows: rows} = Repo.query!("SELECT id FROM artifact_dedupe_scratch")
    survivors = Enum.map(rows, fn [bin] -> Ecto.UUID.load!(bin) end)

    assert survivors == [newer], "expected only the newest row to survive dedupe"
  end
end
```

**Anti-vacuity proof:** the second test seeds the exact precondition that breaks the real migration (`CREATE UNIQUE INDEX` on duplicate keys) and asserts the dedupe both (a) reduces to one row and (b) keeps the **newest** — if the dedupe SQL's comparison is inverted (keeps oldest) or the `<` is wrong, `survivors == [newer]` fails. If the dedupe is missing entirely, `count` stays 2 / `survivors` has 2 elements and the assertion fails. So the test goes red precisely when the fix is wrong — not merely green when it's right.

> Executor note: keep the test's `@dedupe_sql` textually identical to the migration's `(run_attempt_id, projection_path)` DELETE (modulo the `artifacts` → `artifact_dedupe_scratch` table name and the `run_attempt_id IS NOT NULL` guard, which the scratch test omits because all seeded rows are non-null). If Robert prefers Option B (run the actual migration body), refactor the dedupe SQL into a shared private function the migration calls and the test invokes, so there's a single source of truth — but that adds coupling; Option A's textual mirroring is simpler and adequate here.

#### Re-calibration

**None.** No TrustScore weight, threshold, or verdict is touched. Migrations don't enter the gate.

#### Green criteria
- `mix test --exclude eval --seed 0` green, including `artifact_projection_dedupe_test.exs`.
- `mix ecto.migrate` succeeds on a fresh DB (the new migration is a clean no-op on empty data — both DELETEs affect 0 rows, both index re-creates succeed).
- `mix ecto.rollback` (one step) succeeds on a fresh DB (the new migration's `down` runs; on empty data the dedupe DELETE affects 0 rows and the unique index recreates cleanly). Run `mix ecto.migrate && mix ecto.rollback && mix ecto.migrate` against a throwaway DB to prove round-trip reversibility — this is the concrete evidence that dr1m.8's reversibility claim is true, not asserted.
- `mix conveyor.eval.scorecard --gate` unchanged (migrations don't affect verdicts).

#### Risks / traps
- **Editing an applied migration trap (the big one):** the seed fact's phrasing ("FIX: dedupe-safe up ... + a real down") reads as "edit `20260620110000`." **Do not.** It may be applied; edit-in-place desyncs `schema_migrations`. Deliver a new forward migration. (Corrected and baked above.)
- **Sandbox-hides-the-bug trap:** any test that relies on the normal empty-start Sandbox DB proves nothing about populated dedupe. The test MUST manufacture duplicates (scratch table or index-drop) to be discriminating. A test that just runs the migration on an empty DB and asserts "no error" is **vacuous** — it passes on the buggy migration too.
- **`created_at` column-name trap:** if the physical column isn't `created_at`, both the migration and the test break silently (the DELETE matches nothing). Verify the column name first.
- **Data-loss-on-down honesty:** the `down` deletes artifact rows to re-uniquify `(sha256,size_bytes)`. That's inherent and acceptable for a rollback, but it MUST be documented in the migration docstring so no one is surprised. Don't pretend `down` is lossless.
- **Latency/urgency trap:** because this only bites on a populated non-Sandbox DB, it's tempting to skip. The honest call: it's low-urgency *today* but a real footgun the moment `conveyor_dev`/prod accumulates artifact rows. Ship it as belt-and-suspenders unless Robert rules durable DB out of M4 scope (the open question below).

---

### Sequencing & exit for sub-stream G

1. **G1** (edge dedup) — higher leverage (real Genome correctness bug that M4's re-run/replay loop will actively trigger). **Always in M4.** Land first.
2. **G2** (migration safety) — latent until a durable DB exists. **CONDITIONAL: resolve Open Decision 13 FIRST.** If a durable, populated, non-Sandbox DB is in scope before M4 ships, G2 lands second (gated on that scope question). If Conveyor stays Sandbox/ephemeral for all of M4 (the likely answer), **G2 DEFERS** to the milestone that introduces the durable run-history DB — file it as a tracked follow-on (parent `dr1m`, label `data-integrity`, body: the forward-only dedupe-safe migration + dedupe-safe `down` from this slice, to ship when a durable DB lands) rather than spending an M4 slice on a latent bug with a scratch-table-only test.

G1 lands as a green commit of M4, after all live-signal sub-streams, since it changes no verdict and blocks nothing. G2, if in scope, lands alongside it. Each is a standalone green commit (TDD: write the red discrimination test first, confirm it fails on `main`, apply the fix, confirm green). Commit trailer ends `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do not commit/push until Robert asks.

**Sub-stream exit (evidence, not assertion):**
- New tests `back_edge_dedup_test.exs` and `artifact_projection_dedupe_test.exs` green under `mix test --exclude eval --seed 0`, AND each proven to go **red** against the unpatched code first (the red→green log is the anti-vacuity evidence).
- `gate_finalizer_test.exs` + the beads_insight/gx reference corpus unchanged (one edge per single finalization still holds; no verdict drift).
- `mix conveyor.eval.scorecard --gate` byte-identical verdict counts before/after both slices (these are bookkeeping fixes; any scorecard delta is a bug).
- `mix ecto.migrate && mix ecto.rollback && mix ecto.migrate` round-trips cleanly on a throwaway DB (proves G2 reversibility).

---

## Sub-stream H — Exit, validation & cost (CI-hard + bounded live + external falsifier)

> **Role of this sub-stream.** H does **not** build trust producers, the hermetic backend, the static-stage gauntlet, or the live gate wiring — sub-streams A–G do. H is the **acceptance harness and the honesty contract** for M4: it defines exactly what "M4 is done" means, encodes the *provable-in-CI* part as hard gates, defines the *only-measurable-live* part as a reported protocol (never a hard gate), builds the external-buggy-commit falsifier probe, sizes the cost, and ships a `DONE.md`-style checklist a zero-context agent can mechanically verify. It is the *last* sub-stream to land (it depends on all of A–G being green) but parts of it (the checklist scaffolding, the cost note, the live-protocol doc, the external-probe harness skeleton) can be built in parallel and only *flip on* once producers exist.
>
> **Why H is separate from F.** Sub-stream F owns the MutantGauntlet static-stage extension and the *content* of the corpus. H owns the **meta-assertion** that the corpus is wired into CI as a fail-closed gate, that abstain *fires for real end-to-end* (not via injected synthetic evidence), and that the numbers we report live are honestly labeled provisional/measured-not-derived. The single most important sentence in this sub-stream: **everything provable for $0 deterministically in CI is a HARD gate; everything that depends on a stochastic live Codex agent is REPORTED, never a hard gate** (ROADMAP §4 and §M1 both warn that coupling a milestone exit to agent reliability is a category error — M1's exit was *wiring stability*, not agent reliability).

---

### Verified seed facts (read the code, confirmed)

All seed facts were verified against the repo before designing. Corrections and confirmations:

- **`mix conveyor.eval.scorecard --gate`** (`lib/mix/tasks/conveyor.eval.scorecard.ex:68-72`): `--gate` exits `ExitCodes.fetch!(:canary_or_eval_false_negative)` = **6** (not 1) iff `Scorecard.healthy?/1` is false; otherwise `:success` = 0. CONFIRMED. *Seed said "ci.yml:91-95"; that is wrong* — `:91-95` in `conveyor.eval.scorecard.ex` is `git_revision/0`, and in `ci.yml` the scorecard gate step is the second-to-last step (after the lift projection, before Credo), not lines 91-95. The plan uses the real anchors below.
- **`Scorecard.healthy?/1`** (`lib/conveyor/eval/scorecard.ex:46,53,96-98`): healthy iff **no** metric has `"status" == "blocking"`. A metric is blocking when built with `blocking: true` and `value != target` (`scorecard.ex:72-94`). So `false_pass_rate` (target 0, blocking) and `replay_fidelity` (target 1, blocking) drive the gate. CONFIRMED.
- **CI emits scorecard inputs** in `ci.yml` via, in order: `mix conveyor.eval.rung0` (E7/E8/E1 incl. `MutantGauntlet.emit!`), `mix conveyor.eval.replay --all` (replay_fidelity), `mix conveyor.eval.lift` (lift projection), then `mix conveyor.eval.scorecard --gate`. CONFIRMED. **Trap:** `MutantGauntlet.emit!()` in `rung0` runs only the **tasks_service** manifest (`@manifest_path "samples/tasks_service/.conveyor/canary/mutants.json"`, `mutant_gauntlet.ex:27`); the beads_insight 7-mutant corpus is exercised only by a test (`mutant_gauntlet_test.exs:50-74`), **not** emitted into the scorecard. So **today the CI gate only protects the tasks_service behavioral subset**. H's full-corpus gate must fix this (Slice H2).
- **`Finalizer` abstain path** (`finalizer.ex:34,65-84`): `result.passed? and abstain?(trust)` → `abstain_gate!` → `RunAttempt` `outcome: :abstained`, status stays `:gated`; `Slice` → `:parked`; **no** provenance edges, **no** trust-bundle minted. CONFIRMED. `outcome: :abstained` is a real enum value (`run_attempt.ex:115`). This is the *exact* observable H asserts on for the end-to-end abstain proof — `run_attempt.outcome == :abstained` and `slice.state == :parked`, queried from the persisted records, **not** from the in-memory `finalized` map.
- **`TrustScore`** (`trust_score.ex:58-65,89,105-110`): `@default_weights %{integrity: 0.30, calibration: 0.20, baseline: 0.20, replay: 0.15, corpus: 0.15}`, `@default_thresholds %{auto_accept: 0.9}`. Auto-accept requires BOTH `trustworthy?/1` (every non-corpus signal unambiguously good) AND `score >= 0.9`. CONFIRMED. H does **not** change weights/threshold itself (that's A–F as they flip signals fail-closed), but H **owns the re-calibration regression assertion**: the known-good reference must still auto-accept at every weight/threshold change (Slice H3 ties this off as a single guarded test).
- **`TrustEvidence`** (`trust_evidence.ex:47-62`): today launders unmeasured signals to the passing token (`calibration(_status) -> :valid`, `baseline(_) -> :green`, `integrity(_) -> "trustworthy"`, `replay(_) -> :none`, `corpus(_) -> nil`). This is the **fail-OPEN** posture M4 flips. H asserts the *result* of those flips (abstain fires) but does not implement them.
- **`MutantGauntlet`** (`mutant_gauntlet.ex`): real-execution discrimination over `known_good` + behavioral (`expected_catch.stage == "test_execution"`) mutants; static mutants recorded as `deferred_static_stage`. `false_pass_rate` (blocking@0) + `mutant_catch_rate` (@1) metrics. CONFIRMED.
- **Hermeticity / docker** (`toolchain_runner.ex:113-130,224-244`): `:docker` backend uses `--network=none`; `hermeticity/1` returns the 4-key map but the honest 6-control `hermeticity_observation` is attached **only** under `:docker` (under `:local` it is omitted so it stays `not_assessed` → non-blocking, never false-claiming hermetic). `docker_available?/0` = `System.find_executable("docker") != nil`. CONFIRMED. This is the "abstain not false-pass when docker absent" substrate the falsifier-probe and live-protocol must respect.
- **Outcomes queryable**: `RunAttempt.outcome` enum (`run_attempt.ex:106-115`) = `[:none?, :needs_rework, :accepted, :rejected, :policy_blocked, :abstained]`; `Slice.state` includes `:parked, :gated, :failed, :policy_blocked, :needs_rework`. CONFIRMED. **`mix conveyor.parked` + `ParkedQueue.abstained/0`** (`conveyor.parked.ex`, `parked.ex:23`) is a ready-made query for parked-rate and the abstain proof — H reuses it, no new query needed.
- **`agent_session`** (`agent_session.ex:67-75`): `cost_estimate :decimal` + `tokens :integer`, `belongs_to :run_attempt`. CONFIRMED (PR #17). H's cost-report queries these.
- **gx has NO `mutants.json`** (only `reference_slice_*.patch` files under `samples/gx/.conveyor/canary/`). **This is a real gap.** The seed/decisions say "the known-good reference (samples/beads_insight + samples/gx) still auto-accepts" — gx can serve as a *known-good auto-accept* reference (run its reference patches through the live gate) but it **cannot** contribute to the *full-corpus zero-false-pass* metric until a gx `mutants.json` exists. H flags this as a blocking dependency on F (or a small H sub-task) and does **not** silently pretend gx is in the corpus. See Risk R-H1.
- **`mix conveyor.run`** (`conveyor.run.ex:16-35`): `mix conveyor.run PLAN.md [--adapter codex|reference_solution]`. **Trap:** the seed wrote `--adapter codex` with no plan path; the task signature is `run([plan_path | args])` — the plan path is **positional and required**. The live protocol below uses `mix conveyor.run samples/beads_insight/conveyor.plan.yml --adapter codex`. `:partial` exits `deterministic_gate_failed`=1; `:passed` exits 0.

---

### Dependencies & ordering

- **Depends on (by key):** `A-trust-producers` (integrity/calibration/baseline real producers + fail-closed flips), `B-abstain-end-to-end` (abstain wired through production Finalizer on real signals), `C-hermetic-gate` (docker `--network=none` gate verification + not_assessed/abstain on docker-absent), `D-replay-corpus` (replay_divergence + corpus_pass_rate producers), `E-live-gate-stages` (all 14 stages live + policy_blocked/critical-stop branches reachable), `F-mutant-gauntlet-static` (static-stage gauntlet + full corpus content incl. gx mutants).
- **H lands LAST.** Rationale: the CI-hard exit can only be asserted once every producer is real and every discrimination test from A–F is green; flipping the full-corpus gate on before F is complete would park the known-good reference and violate the incremental fail-closed posture.
- **Internal ordering within H:** H1 (checklist scaffold + cost note, parallel-safe, no gate) → H2 (full-corpus CI gate wiring, after F) → H3 (re-calibration regression guard, after A–F weight changes settle) → H4 (end-to-end abstain proof, after B) → H5 (external falsifier probe, after A–F activation) → H6 (bounded-live protocol + measurement task, after E) → H7 (DONE checklist finalize + falsifier-as-CI-canary, after H2–H6).

---

### br issues closed

- **`dr1m.7`** — *eval verifier: acceptance_locked passes vacuously on zero tests → silent false-PASS.* H4's end-to-end abstain proof + H2's full-corpus gate make the "zero-tests vacuous pass" a *measured* false-pass that the gate must catch (and the gx-no-mutants gap is exactly this class). Closed when the full-corpus gate is zero-false-pass **and** a planted zero-test mutant is in the corpus and caught/abstained. *(Note: if F already claims dr1m.7 via the gauntlet content, H instead **co-verifies** it via the CI gate — coordinate with F; do not double-close.)*
- **`dr1m.6.2` (partial)** — *least-trusted-first ordering untested + nondeterministic ParkedQueue dedup.* H4 reuses `ParkedQueue.abstained/0` and adds the determinism assertion (ordering stable, no dup) as part of the abstain proof. Close only if F/G have not already; otherwise leave to G.
- H **opens** (does not close) a new tracking issue **`m4.exit`** — "M4 exit checklist + bounded-live report + external falsifier" — as the umbrella the DONE.md maps to. (File with `br` when H starts; link under the M4 epic once M4 is filed.)

> Honesty note: H is a *meta/acceptance* sub-stream, so it legitimately closes few br issues directly — most M4 br issues are owned by A–F. H's deliverable is the *proof that they are all actually done*, which is higher-leverage than any single issue.

---

### H1 — Exit-checklist scaffold + cost/budget note (parallel-safe, NO gate)

**Goal:** stand up the machine-checkable M4 DONE checklist and the cost note *before* the producers exist, so every later sub-stream has a single target to make green. Zero behavior change; no CI gate flips here.

**Files to create:**

- `docs/5_milestones/M4-DONE.md` (new). The single source of truth for "M4 is done." Two clearly separated parts:
  - **Part A — CI-HARD (provable for $0, deterministic).** Each item is a literal command + expected exit code/output, plus the test name that backs it. A zero-context agent runs the command, checks the code, ticks the box. No judgment.
  - **Part B — LIVE-MEASURED (reported, NOT a gate).** Each item is "run protocol X, record numbers into `eval/live/<date>.json`, compare to the provisional target, **note** pass/miss — does not block M4." Explicitly labeled "stochastic; informational."
  Each checklist line carries a `→ §4:<bar-item>` back-reference to the ROADMAP §4 exit bar (mapping table below).
- `docs/5_milestones/M4-COST.md` (new). The token/$ estimate + dev-phase not-to-exceed budget note (ROADMAP §6 asks for exactly this before repeated live runs). Contents derived in the Cost section below.

**`M4-DONE.md` Part A skeleton (filled in by H2–H7):**

```
# M4 — Definition of Done

## Part A — CI-HARD (deterministic, $0; these BLOCK M4)
- [ ] A1 Full-corpus zero false-pass    → §4:gate-honesty
      $ MIX_ENV=test mix conveyor.eval.scorecard --gate ; echo $?   # expect 0
      backed by: Conveyor.Eval.MutantGauntletTest (tasks_service + beads_insight + gx),
                 Mix.Tasks.Conveyor.Eval.ScorecardFullCorpusTest
- [ ] A2 Every A–F discrimination test green
      $ MIX_ENV=test mix test --include eval --seed 0 ; echo $?     # expect 0
- [ ] A3 Abstain fires end-to-end on a real broken signal → §4:abstain-fires
      backed by: Conveyor.M4AbstainEndToEndTest
      (broken integrity producer → Finalizer → run_attempt.outcome==:abstained, slice.state==:parked,
       asserted from PERSISTED records, NOT injected synthetic evidence)
- [ ] A4 Re-calibration regression: known-good reference still auto-accepts at final weights/threshold
      backed by: Conveyor.Gate.TrustScoreCalibrationTest (beads_insight + gx reference evidence)
- [ ] A5 Hermeticity-absent abstains (not false-passes) → §4:gate-honesty (honesty axis)
      $ MIX_ENV=test mix conveyor.eval.scorecard --gate ; echo $?   # hermetic_abstain_proof blocking@0, dockerless runner
      backed by: Conveyor.HermeticAbstainTest + the hermetic_abstain_proof scorecard metric (D2;
                 docker-absent injected → REAL assembler→verify→finalizer → persisted :abstained, $0)
- [ ] A6 External-falsifier probe catches planted defects (post-activation; CI canary form)
      $ MIX_ENV=test mix conveyor.eval.falsifier --check ; echo $?  # expect 0 (caught >= floor)
      backed by: Conveyor.Eval.FalsifierProbeTest

## Part B — LIVE-MEASURED (stochastic; REPORTED, does NOT block M4)
- [ ] B1 first-pass-gate-success measured on beads_insight + gx (target ≥70% PROVISIONAL) → §4:first-pass≥70%
- [ ] B2 material-dispute-rate measured (target <20% PROVISIONAL) → §4:dispute<20%
- [ ] B3 parked-rate measured (target <15% PROVISIONAL) → §4:parked<15%
- [ ] B4 Demonstrated lift on defects-caught/honest-abstention vs bare agent → §4:demonstrated-lift
      (record into eval/live/<date>.json; protocol in docs/5_milestones/M4-LIVE-PROTOCOL.md)
```

**Discrimination test:** none for H1 (it is documentation scaffold). The anti-vacuity guard is structural: H7 adds a meta-test `docs/M4-DONE has no unchecked Part-A box at merge` only conceptually — in practice the CI-hard boxes A1–A6 are each backed by a real failing-when-broken test built in H2–H7. H1 alone introduces no green-washing because it asserts nothing.

**Green criteria:** `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` clean (docs-only + no code). No scorecard/gate change.

**Risks/traps:** the trap to avoid is writing a checklist whose Part-A items are *prose* ("gate works") rather than a *command + expected code*. Every Part-A line MUST be mechanically runnable. Carry forward: "looks-wired-but-vacuous" applies to checklists too — a box that no test backs is theater.

---

### H2 — Full-corpus CI-hard zero-false-pass gate (after F)

**Goal:** make `mix conveyor.eval.scorecard --gate` actually protect the **full** behavioral+static corpus across **all three** samples (tasks_service, beads_insight, gx), so a real false-pass anywhere turns the gate red. Closes the seed-confirmed gap that today only tasks_service is emitted.

> **OWNERSHIP NOTE (F18):** the `@suite`-collision fix (per-sample suite/key parameterization so the three samples don't overwrite one scorecard input) is the PRECONDITION for E10's own multi-sample green criterion and is owned there (E10/E0). H2 owns the **CI corpus-breadth discovery** (`CorpusGauntlet` glob over `samples/*/.conveyor/canary/mutants.json` + the gx-gap honesty) and ASSERTS the gate E10 established — H2 does not re-establish a competing `--gate`. C5 and H7 likewise ASSERT the single E10-owned gate. This removes the triple-claimed-ownership hazard (E10 vs C5 vs H2).

**Current behavior → target:**

- `Mix.Tasks.Conveyor.Eval.Rung0.run/1` (`conveyor.eval.rung0.ex:28`) calls `MutantGauntlet.emit!()` with **default opts** → only `samples/tasks_service`. **Target:** emit the gauntlet for **every** sample that has a `mutants.json`, each writing a distinct scorecard input (e.g. `mutant_gauntlet_tasks_service.json`, `mutant_gauntlet_beads_insight.json`, `mutant_gauntlet_gx.json`). The `@suite` field must be parameterized so the three inputs don't collide (today `@suite "mutant_gauntlet"` is hardcoded → all three would overwrite the same `mutant_gauntlet.json` and the same metric `key`).
- **New module `Conveyor.Eval.CorpusGauntlet`** (`lib/conveyor/eval/corpus_gauntlet.ex`):
  - Responsibility: discover every `samples/*/.conveyor/canary/mutants.json`, run `MutantGauntlet.run/1` per manifest (with the right `plan_path` + venv), and aggregate into one corpus report + per-sample scorecard metrics.
  - Key signatures:
    - `@spec manifests() :: [%{sample: String.t(), manifest_path: String.t(), plan_path: String.t()}]` — globs `samples/*/.conveyor/canary/mutants.json`; pairs each with its sibling `conveyor.plan.yml`.
    - `@spec run(keyword()) :: map()` — `%{"schema_version" => "conveyor.eval_corpus_gauntlet@1", "samples" => [report], "false_passes_total" => n, "false_pass_rate" => f, ...}`.
    - `@spec metrics(map()) :: [map()]` — one `false_pass_rate` metric **per sample** (suite = `"mutant_gauntlet_<sample>"`, `blocking: true`, target 0) **plus** one aggregate `corpus_false_pass_rate` (blocking@0). Per-sample blockers mean a false-pass on *any* sample reddens the gate, and the failing sample is named in the metric `detail`.
    - `@spec emit!(keyword()) :: map()` — writes per-sample inputs via `Scorecard.write_input!`.
  - Called from: `Mix.Tasks.Conveyor.Eval.Rung0.run/1` (replace the single `MutantGauntlet.emit!()` with `CorpusGauntlet.emit!()`). Falls back gracefully (a sample without `mutants.json` is simply absent — never silently "passes").
- **`MutantGauntlet`** needs a `:suite` opt (or `CorpusGauntlet` builds the metric directly). Minimal change: add `opts[:suite]` threaded into `metrics/2` and `emit!/1`'s `write_input!` name. Current `@suite "mutant_gauntlet"` becomes the default.
- **gx gap:** gx has no `mutants.json`. **Decision (H, overridable):** H2 requires F to deliver `samples/gx/.conveyor/canary/mutants.json` (≥1 behavioral mutant per gx slice, mirroring beads). If F defers gx mutants, H2 ships with tasks_service+beads only **and the DONE checklist A1 explicitly records "gx behavioral mutants: NOT in corpus (gap, tracked)"** — H never silently claims full coverage it doesn't have. Recommended: do not let M4 exit claim "full canary corpus" without gx mutants; either F supplies them or M4's gate-honesty claim is scoped to "two of three greenfield samples" in writing.

**Discrimination test(s):**

- **File:** `test/mix/tasks/conveyor_eval_scorecard_full_corpus_test.exs` — `Conveyor.Eval.ScorecardFullCorpusTest`. `@moduletag :eval`.
- **GOOD-signal case** (`"the real corpus is zero-false-pass → scorecard healthy → gate exits 0"`): run `CorpusGauntlet.emit!()` against the real samples, then `Scorecard.load_inputs/1 |> Scorecard.build(...)`; assert `Scorecard.healthy?(scorecard) == true` and that per-sample `false_pass_rate == 0.0`. Expected outcome: **accept** (gate green).
- **BROKEN-signal case** (`"a planted false-pass in the corpus → scorecard BLOCKED → gate exits 6"`): this is the anti-vacuity heart. Inject **one** synthetic per-sample metric with `false_pass_rate = 0.5, blocking: true, target 0` into a temp inputs dir (simulating a mutant the gate let through), build the scorecard, assert `Scorecard.healthy?/1 == false` **and** the canonical blocker names the offending sample. Then drive the actual task: set `Process.put(:conveyor_eval_scorecard_exit_fun, fn code -> send(self(), {:exit, code}) end)`, run `Mix.Tasks.Conveyor.Eval.Scorecard.run(["--gate", "--inputs", tmp_dir])`, assert it sent `{:exit, 6}`. Expected outcome: **reject** (gate red, exit 6). *This proves the gate FAILS when it should — without it, the gate is decorative.*
- **Negative-control assertion** (anti-vacuity for the test itself): assert that **removing** the planted blocker flips the same task back to exit 0, so we know the red came from the blocker, not from an unrelated input.

**Re-calibration steps:** none — H2 changes the *corpus breadth*, not TrustScore weights/threshold. (Weight/threshold changes are owned by A–F; H3 regression-guards them.)

**Green criteria:**
- `MIX_ENV=test mix test --include eval --seed 0` includes `ScorecardFullCorpusTest` and `MutantGauntletTest` (all three samples) green.
- `MIX_ENV=test mix conveyor.eval.rung0 && MIX_ENV=test mix conveyor.eval.scorecard --gate` exits **0** on the real (clean) corpus.
- The planted-false-pass branch of the discrimination test proves exit **6**.

**Risks/traps:**
- **Collision trap (real, found in code):** `@suite "mutant_gauntlet"` + a single metric `key "false_pass_rate"` means three samples emitted into the same filename/key would silently overwrite each other → only the last sample is gated. The per-sample suite/key parameterization is *load-bearing*, not cosmetic.
- **gx-no-mutants trap:** glob-based discovery will simply skip gx (no manifest) — which is *honest* but must be *visible* in the DONE checklist, else "full corpus" is a vacuous claim.
- **Venv/runtime trap:** beads + gx gauntlets need a working pytest venv in CI (the existing `mutant_gauntlet_test.exs` resolves `samples/tasks_service/.venv/bin`). Confirm CI's `actions/setup-python` + the venv build covers all three samples' `requirements.lock`; a missing venv must make the gauntlet *error loudly* (test failure), never "0 mutants → vacuously 0 false-pass."

---

### H3 — Re-calibration regression guard (after A–F weight/threshold changes settle)

**Goal:** one durable test that fails the instant any weight/threshold change (made by A–F as signals flip fail-closed) would stop the **known-good reference** from auto-accepting. This is the mechanical enforcement of the ratified posture: "re-tune weights/threshold against that reference at each step; the known-good reference must still auto-accept."

**Files:**

- `test/conveyor/gate/trust_score_calibration_test.exs` — `Conveyor.Gate.TrustScoreCalibrationTest`. (Pure, $0, **not** `:eval`-tagged — runs in the default `mix test` so a weight change breaks the *base* suite immediately, not only under `--include eval`.)
- New fixture module `Conveyor.GoldenReferenceEvidence` (`test/support/golden_reference_evidence.ex`): the canonical *fully-good* evidence map for each known-good reference, the exact map a clean known-good run of beads_insight / gx **must** produce once all real producers exist:
  - `@spec beads_insight() :: TrustScore.evidence()` → `%{integrity_verdict: "trustworthy", calibration_status: :valid, baseline_status: :green, replay_divergence: :none, corpus_pass_rate: <real measured rate or nil cold-start>}`.
  - `@spec gx() :: TrustScore.evidence()` → same shape.
  - These are the *reference* evidence maps; H3 keeps them in sync with what D's `corpus_pass_rate` producer actually emits for the reference (so the test stays honest, not a frozen fiction).

**Discrimination test(s):**

- **GOOD-signal** (`"the known-good reference auto-accepts at the SHIPPED weights/threshold"`): `TrustScore.evaluate(GoldenReferenceEvidence.beads_insight())` (and gx) using the **defaults the code ships with** (no override) → assert `result.band == :auto_accept` and `result.score >= result.thresholds.auto_accept`. Expected: **accept**. *If A–F change `@default_weights`/`@default_thresholds` such that the reference would abstain, this fails — exactly the guardrail we want.*
- **BROKEN-signal** (`"a single degraded reference signal abstains (fail-closed proven)"`): take the golden reference, set `integrity_verdict: "suspect"` (or `:replay_divergence => :diverged`), evaluate at shipped defaults → assert `result.band == :abstain`. Expected: **abstain**. This proves the threshold is not so loose that a real negative slips through (the dual anti-vacuity: the gate must accept good AND reject bad at the *same* shipped policy).
- **Policy-digest pin** (`"policy_digest changes iff weights/threshold change"`): assert the shipped `policy_digest` equals a recorded constant; when A–F intentionally change weights, they update this constant **in the same commit** — so the diff makes the calibration change reviewable (Robert can see/override the exact numbers). This is the "decisions baked, overridable" surface.

**Re-calibration steps (the template A–F follow, enforced here):**
1. State numbers **before**: record current `@default_weights`/`@default_thresholds` and the reference `score` (e.g. integrity 0.30 / calibration 0.20 / baseline 0.20 / replay 0.15 / corpus 0.15; threshold 0.90; reference score = 1.0·all-good = `0.30+0.20+0.20+0.15+0.15 = 1.00` when corpus_pass_rate present, or `0.30+0.20+0.20+0.15+0.5·0.15 = 0.925` on a cold-start with corpus defaulting to 0.5 — **still ≥ 0.90, still auto-accepts**, which is why cold-start corpus must never block, per `trust_score.ex:25-27,105-110`).
2. Make the change (flip a signal fail-closed).
3. State numbers **after**; recompute the reference score by hand.
4. Run `TrustScoreCalibrationTest` — the GOOD-signal case must stay green (reference still ≥ threshold). If it goes red, the change parked the reference → **forbidden**; re-tune (lower threshold or re-weight) until green, document why.
5. Update the `policy_digest` pin constant in the same commit.

> **Cold-start arithmetic check (verified against `trust_score.ex`):** with corpus absent, `corpus_score(_) -> 0.5`, contributing `0.5·0.15 = 0.075`. All other signals good = `0.30+0.20+0.20+0.15 = 0.85`. Total `0.925 ≥ 0.90` → `trustworthy?/1` true (corpus excluded from the hard gate) → **auto_accept**. Confirmed the known-good reference auto-accepts even with no corpus history. This is the `loop_integrity` invariant H3 protects.

**Green criteria:** `mix test --seed 0` (default suite, no `--include eval`) green including `TrustScoreCalibrationTest`. Any A–F weight change that breaks it blocks that A–F commit.

**Risks/traps:** the golden reference evidence must be the *real* output of the producers, not a hand-wavy all-`"trustworthy"` map — otherwise H3 green-washes (passes because the fixture is rigged good). Mitigation: in H4/H6, cross-check that a *real* clean beads_insight run actually produces an evidence map equal to `GoldenReferenceEvidence.beads_insight()` (assert the live evidence == the fixture). If they diverge, the fixture is a lie.

---

### H4 — End-to-end abstain proof from a REAL broken signal (after B)

**Goal:** prove abstain fires **through the production Finalizer on a real (broken) producer signal**, observed from *persisted* `run_attempt.outcome`/`slice.state`, not from injected synthetic `:trust_evidence`. The existing `gate_finalizer_test.exs:184-211` proves abstain via **injected** evidence — that is necessary but *vacuous as an end-to-end claim*: it never exercises the producer→evidence→finalizer chain. H4 closes that gap.

**Current behavior → target:**

- `gate_finalizer_test.exs:184-211` ("ADR-23: a passed gate with low trust evidence abstains") sets `:trust_evidence` *directly* in the context map. **This proves the Finalizer's scoring branch, NOT the production wiring.** Target: a test where the broken signal originates from a **real producer station's output** (the same `output` map `TrustEvidence.from_run_output/1` reads at `trust_evidence.ex:23-33`), so the chain producer → `from_run_output` → `TrustScore.evaluate` → `Finalizer` abstain → persisted `:abstained`/`:parked` is exercised whole.

**Files:**

- `test/conveyor/m4_abstain_end_to_end_test.exs` — `Conveyor.M4AbstainEndToEndTest`, `use Conveyor.DataCase, async: false` (needs the DB to persist + re-read; mirrors `gate_finalizer_test.exs` setup). `@moduletag :eval` (it drives the production loop / real producer).

**Discrimination test(s):**

- **BROKEN-signal case** (`"a real RED baseline producer output drives the Finalizer to abstain and PARK (persisted)"`):
  1. Build a run output map the way a real station writes it: `output = %{"baseline_health_status" => "red", "test_pack_calibration" => %{"status" => "valid"}, ...}` — i.e. set the **broken** signal via the production key `"baseline_health_status"` (the real producer's contract from `trust_evidence.ex:28`), **not** via a synthetic `:trust_evidence` map.
  2. Assemble evidence through the *production* path: `trust_evidence = TrustEvidence.from_run_output(output)`. (Assert `trust_evidence.baseline_status == :red` to prove the producer key actually drove it.)
  3. Run the real Finalizer: `Gate.run!` a passing stage + `Finalizer.finalize!(result, Map.put(ctx, :trust_evidence, trust_evidence))`.
  4. **Assert from persisted records** (not the returned map): `get_by_id!(RunAttempt, id).outcome == :abstained`; `get_by_id!(Slice, id).state == :parked`; `Ash.read!(CodeProvenanceEdge) == []` (no provenance minted); no `"trust-bundle"` artifact. Expected outcome: **park/abstain**.
  5. **Reuse `ParkedQueue.abstained/0`**: assert the run now appears in the parked queue with `band: "abstain"` (ties the operator-facing payoff into the proof, and exercises `dr1m.6.2`'s dedup/ordering on a real row).
- **GOOD-signal case** (`"the same chain with all-good real producer output AUTO-ACCEPTS"`): identical wiring but `output` has `"baseline_health_status" => "green"` and all other producer keys good → `from_run_output` → evaluate → `Finalizer` → assert `outcome == :accepted`, `slice.state == :gated`, **and** provenance edges + trust-bundle ARE minted. Expected: **accept**. This is the paired anti-vacuity: the chain abstains on bad AND accepts on good, end-to-end, through the same code.

**Why this is non-vacuous (the carried-forward trap):** the injected-evidence test could pass forever even if no production station ever writes `"baseline_health_status"`. H4 asserts the **producer key** (`output["baseline_health_status"]`) is what drives the verdict — so if B's producer stops writing that key, H4 goes red. *That* is the difference between "looks wired" and "is wired."

**Re-calibration steps:** none (H4 doesn't touch weights). But H4 **depends on** H3's golden reference: the GOOD-signal case's all-good `output` must yield evidence equal to `GoldenReferenceEvidence.*` — H4 asserts that equality (the cross-check from H3's risk note).

**Green criteria:** `MIX_ENV=test mix test --include eval --seed 0` green incl. `M4AbstainEndToEndTest`; DONE checklist A3 ticks.

**Risks/traps:** the temptation is to keep using injected `:trust_evidence` "because the test is simpler." That reproduces the vacuity. The test MUST route through `TrustEvidence.from_run_output/1` from a producer-shaped `output` map. Second trap: asserting on the in-memory `finalized.run_attempt.outcome` instead of a fresh `get_by_id!` re-read — the in-memory struct can be right while the DB write silently failed (this is *exactly* the dr1m.1.1 class of bug). Always re-read from the DB.

---

### H5 — External-buggy-commit falsifier probe (after A–F activation)

**Goal:** run the **activated** M4 gate against a curated set of *known-buggy* commits to measure catch-rate as a cheap **thesis-falsification** (ROADMAP §7 OPEN DECISION = INCLUDE). The thesis is "Conveyor's gate catches real defects a bare agent would miss"; this probe is the falsifier — if the activated gate *can't* catch planted real defects, the thesis is wounded and we want to know loudly. Only meaningful **after** activation (the degenerate fail-open gate would mislead).

**Target selection (decision, H — the M4 hard falsifier must be INDEPENDENT of the F gauntlet corpus, or it is circular):**

> **The circularity trap this resolves (carried from the F-mutant-gauntlet sub-stream):** the F gauntlet (`samples/*/.conveyor/canary/mutants/*.patch`) is the corpus the gate was *tuned against* — every `expected_catch` was reconciled to a real stage category in E3/E5/E10. If the M4 hard falsifier simply re-runs those same patches, it proves nothing the gauntlet did not already prove; it is a near-tautology of the harness it is supposed to be independent of. So the M4 hard falsifier uses a SEPARATE, FIXED set of defects the gate was NOT built against.

1. **Primary, sterile, deterministic, and INDEPENDENT of F (recommended — ships in M4 as the hard canary): a small FIXED set of 4 in-repo reverted-known-good slices under a dedicated `falsifier/` dir, DISTINCT from the F canary mutants.** Ship `samples/falsifier/` (or `eval/falsifier/targets/`) containing exactly **4 named patch files**, each a real defect of a distinct class the activated gate must catch, each with an `expected_catch` that is NOT one of the F mutant ids:
   - `falsifier-01-acceptance-regression.patch` — silently weakens a passing acceptance assertion in a reference slice → `expected_catch: test_execution` (the test no longer asserts the behavior).
   - `falsifier-02-unredacted-secret.patch` — introduces an unredacted secret (e.g. an API-key literal) into a gate-visible artifact → `expected_catch: secret_safety/unredacted_secret` (rejects/parks).
   - `falsifier-03-artifact-hash-mismatch.patch` — tampers a run artifact so its recorded digest no longer matches its content → `expected_catch: run_check/artifact_digest_mismatch` (parks).
   - `falsifier-04-policy-edit.patch` — edits a protected policy file → `expected_catch: policy_compliance/policy_file_change` (policy_blocked).
   These are applied to a reference-good sample and run through the **full activated gate** (all 14 stages + TrustScore + IntegritySentinel). The falsifier asserts the gate does **not** auto-accept any of them (each must fail, abstain, or policy-block), AND that each is caught for its named `expected_catch` (not for an incidental reason). **All 4 targets are deliberately orthogonal to BOTH the F gauntlet corpus AND C5's planted integrity-probe defects** (mount_boundary/mapping) — they exercise `test_execution`, `secret_safety`, `run_check`, and `policy_compliance` so the falsifier proves independent coverage rather than re-running C5's or F's own planted defects. Sterile ($0 LLM, deterministic, no external repo risk), uses defects the gate was NOT tuned against, and tests the *activated* gate (not the gauntlet's `test_execution` subset). The count (4) and target list above are stated exactly so a zero-context agent can build them. **This is the falsifier shipped in M4.**
2. **Secondary, higher-realism (flag as a Track-B / post-M4 follow-on, NOT M4-blocking): a small curated set of public-repo bug-fix commits reverted into a buggy state.** Pick 3–5 commits from a permissively-licensed Python repo where a bug-fix commit has a clear failing test; check out `parent^` (buggy) state, run the gate. Higher realism, but (a) needs network/checkout infra, (b) is not sterile, (c) introduces archetype/brownfield generalization that ROADMAP §4's corpus caveat explicitly puts OUT of the serial bar. **Recommendation: do NOT block M4 on (2); ship (1) in CI as a hard canary, file (2) as a follow-on falsifier under the deferred Verifier-as-product backlog (filed in H7 — see the br-creation action there).**

**Files / module:**

- New module `Conveyor.Eval.FalsifierProbe` (`lib/conveyor/eval/falsifier_probe.ex`):
  - Responsibility: apply each known-buggy patch to a fresh workspace, run the **full activated gate** (the production stage set, not just `TestExecution`), classify the verdict, and report catch-rate + any abstains.
  - Key signatures:
    - `@spec targets() :: [%{id: String.t(), sample: String.t(), patch_ref: String.t(), expected_catch: %{stage: String.t(), category: String.t()}, expected: :must_not_accept}]` — derived from the dedicated **`falsifier/` target dir (the 4 fixed reverted-known-good slices above), NOT the F gauntlet manifests.** This is deliberate: re-using F's corpus would make the falsifier circular (it re-runs the patches the gate was tuned against). Each target carries a named `expected_catch` distinct from any F mutant id, asserted by the probe so a catch-for-the-wrong-reason counts as a false-accept.
    - `@spec run(keyword()) :: map()` — `%{"schema_version" => "conveyor.eval_falsifier@1", "total" => n, "caught" => c, "abstained" => a, "false_accepts" => fa, "catch_rate" => f, "cases" => [...]}` where a case is "caught" if the gate failed it OR abstained/parked it (an honest abstain is a *win* for the thesis — the factory did not auto-merge a defect), and a `false_accept` is the falsifier hit (gate auto-accepted a known-buggy patch).
    - `@spec metrics(map()) :: [map()]` — `false_accept_rate` (suite `"falsifier"`, **blocking@0**) + `catch_rate` (@1, warn).
    - `@spec emit!(keyword()) :: map()`.
  - Called from: a new mix task `Mix.Tasks.Conveyor.Eval.Falsifier` (`lib/mix/tasks/conveyor.eval.falsifier.ex`) — `mix conveyor.eval.falsifier [--check]`. `--check` exits non-zero (reuse `:canary_or_eval_false_negative`=6) if `false_accepts > 0` or `catch_rate < floor`. Also wired into `rung0`/CI as a hard canary (Part A item A6) **only after activation** (gated behind a `@moduletag` so it doesn't run pre-activation and mislead).

**Discrimination test(s):**

- **File:** `test/conveyor/eval/falsifier_probe_test.exs` — `Conveyor.Eval.FalsifierProbeTest`, `@moduletag :eval`.
- **BROKEN/defect case** (`"every falsifier target is caught or abstained for its named reason — zero false-accepts"`): `report = FalsifierProbe.run()`; assert `report["false_accepts"] == 0` and `report["catch_rate"] == 1.0` over the 4 fixed `falsifier/` targets (these are defects the gate was NOT tuned against, so a 1.0 floor is a genuine independent check, not a re-run of F's corpus). For each case assert `not case["auto_accepted"]` AND `case["caught_by"] == case["expected_catch"]` (caught for the named reason, not incidentally). Expected outcome: **reject/abstain** for every defect.
- **Anti-vacuity case** (`"the probe FAILS when a defect would be auto-accepted (negative control)"`): construct a synthetic "defect" that is actually benign/known-good (the reference patch itself) and assert the probe **does** auto-accept it (`auto_accepted == true`) — proving the probe distinguishes buggy from clean and isn't just "rejects everything." Without this, a probe that rejects all inputs would vacuously show catch-rate 1.0. Expected outcome for the clean control: **accept**. *This is the critical anti-vacuity: the probe must accept good and reject bad, or its catch-rate is meaningless.*

**Where results live:** `eval/falsifier/<revision>.json` (committed report, mirroring `eval/lift/`); the blocking metric flows into the scorecard so a regression (a newly-slipped defect) reddens CI. The human-readable catch-rate goes into `M4-DONE.md` Part A (A6) once activation lands.

**Re-calibration steps:** none directly, but the `catch_rate` **floor** is a number H7 sets from the *first real activated run* (measured-not-derived); record before/after in `M4-COST.md`/`M4-DONE.md` and treat as provisional.

**Green criteria:** `MIX_ENV=test mix test --include eval --seed 0` incl. `FalsifierProbeTest` green; `mix conveyor.eval.falsifier --check` exits 0 on the real corpus; the negative-control branch proves the probe rejects when it should.

**Risks/traps:**
- **"Rejects everything looks like 100% catch" trap (primary):** without the benign negative control, a probe that abstains on *everything* (e.g. because hermeticity is `not_assessed` and everything parks) shows catch-rate 1.0 vacuously. The negative control (clean patch must auto-accept) is non-negotiable.
- **Pre-activation misleading-signal trap:** the seed/ROADMAP both warn the *degenerate* gate would mislead. The probe test MUST be gated to run only after A–F activation (tag it, and the CI canary A6 only flips on in H7 once the activated gate is the one under test). Running it against the fail-open gate would either falsely pass (everything "caught" because everything happens to fail) or falsely reassure.
- **Sterility trap:** keep M4's hard probe to the in-repo sample mutants (sterile, $0, deterministic). The public-repo variant is realism-rich but non-sterile and brownfield — explicitly a post-M4 follow-on, not an M4 gate.

---

### H6 — Bounded-live measurement protocol + reporting task (after E)

**Goal:** define the EXACT live protocol (commands, run count, what to query, where results land) to MEASURE first-pass-gate-success / dispute-rate / parked-rate / lift on real Codex — and ship a task that turns the dev DB into a committed report. **Reported, never gated** (ROADMAP §4 + §M1: do not couple a milestone exit to stochastic agent reliability).

**Files:**

- `docs/5_milestones/M4-LIVE-PROTOCOL.md` (new): the runbook. Exact contents:
  - **Pre-flight:** confirm `codex` adapter is reachable; confirm a clean dev DB (`MIX_ENV=dev mix ecto.reset` or snapshot the current `run_attempt`/`agent_session` max-ids so the report can scope to *this* run). Record the git revision under test.
  - **Run set (decision, H):** **5 runs** total — **3 on `samples/beads_insight/conveyor.plan.yml`** + **2 on `samples/gx/conveyor.plan.yml`**, each `MIX_ENV=dev mix conveyor.run <plan> --adapter codex`. Rationale: beads is the primary §4 corpus target; gx is the second greenfield target the §4 caveat asks for to de-risk over-fitting; 5 runs is enough to *measure* (report a rate) without pretending it's the §4 "5 consecutive green" bar (that bar is M6, ≥20-slice, and is explicitly NOT in M4). This is **measurement, not the exit bar.**
  - **Exact command (corrected from seed):** `MIX_ENV=dev mix conveyor.run samples/beads_insight/conveyor.plan.yml --adapter codex` (plan path is **positional & required** — the seed's `--adapter codex` alone would `Mix.raise(usage())`).
  - **What to query** (ground truth from the DB, not the task's stdout summary): see the report task below.
  - **Where results land:** `eval/live/<YYYY-MM-DD>-<rev>.json` (committed), plus a human summary appended to `M4-DONE.md` Part B with each number labeled `[measured]` and its provisional target labeled `[provisional, not derived]`.
- New task `Mix.Tasks.Conveyor.Eval.LiveReport` (`lib/mix/tasks/conveyor.eval.live_report.ex`) — `mix conveyor.eval.live_report [--since-run-attempt-id N] [--out PATH]`:
  - Responsibility: query the dev DB and emit `conveyor.eval_live@1`. **DB-backed** (unlike the other eval tasks; it reads real run history), so it `Mix.Task.run("app.start")`.
  - Queries (Ash/`Conveyor.Factory`):
    - **first-pass-gate-success** = (# run_attempts with `outcome == :accepted` on **attempt_no == 1**) / (# slices attempted). Read `RunAttempt.outcome` + `attempt_no` (`run_attempt.ex`).
    - **eventual-gate-success** = (# slices ever `outcome == :accepted`) / (# slices attempted).
    - **parked-rate** = (# slices `state == :parked`) / (# slices attempted) — or reuse `ParkedQueue.abstained/0` count over the run window.
    - **material-dispute-rate (proxy — scoped to LIVE Codex rejections ONLY, NOT the reference; F27):** computed over the LIVE Codex runs' rejections as **false-reject-vs-golden** = (# gate-rejections of LIVE Codex output that the golden reference solution would have passed) / (# live Codex rejections). **Why scoped to live Codex, not the reference:** on the reference itself the proxy is structurally near-zero by construction (the reference IS the golden solution run through the gate that H3/H4 require to ACCEPT it), so it would just re-confirm `loop_integrity` and measure nothing about dispute. Restricting it to live Codex non-golden output makes it actually measure the gate's rejection behavior on real, non-golden patches. **Honest caveat:** true "material dispute" needs a human/oracle verdict on whether the gate was RIGHT to reject; the false-reject-vs-golden proxy is a stand-in, not the human-dispute metric (deferred to the parked-queue review loop, Track-B). If there are zero live Codex rejections in the window, report "no data" rather than a fabricated 0.0. Label every reported value `[proxy, live-Codex-only]`.
    - **cost** = sum `agent_session.tokens` + `agent_session.cost_estimate` over the run window (join `agent_session.run_attempt_id` → the run's attempts). Reports total tokens and `$` so the live pass has a real cost line.
    - **lift (defects-caught/honest-abstention)** = compare M4-gate outcomes to a **bare-agent arm** (the `reference_solution` adapter or the recorded vanilla lift seed in `eval/lift/`) on the same plan: # defects the M4 gate caught/abstained that the bare run auto-accepted. Reuse `LiftDuel` plumbing where possible.
  - Output map: `%{"schema_version" => "conveyor.eval_live@1", "runs" => n, "first_pass_gate_success" => f, "eventual_gate_success" => f, "parked_rate" => f, "false_reject_vs_golden" => f, "tokens_total" => i, "cost_estimate_total" => d, "lift" => %{...}, "targets" => [...], "git_revision" => sha}`.

**Discrimination test(s):**

- **File:** `test/mix/tasks/conveyor_eval_live_report_test.exs` — `Conveyor.Eval.LiveReportTest`, `use Conveyor.DataCase`. (Not `:eval`-tagged; it tests the *query logic* against **seeded DB fixtures**, deterministically — it must NOT actually invoke Codex.)
- **GOOD case** (`"computes first-pass/parked/cost from seeded run_attempts + agent_sessions"`): seed 4 slices with known outcomes (2 accepted on attempt 1, 1 accepted on attempt 2, 1 parked) + agent_sessions with known tokens/cost; run the report; assert `first_pass_gate_success == 0.5`, `eventual_gate_success == 0.75`, `parked_rate == 0.25`, `tokens_total ==` the seeded sum. Expected: exact numbers.
- **BROKEN/empty case** (`"an empty run window reports zeros, not a crash or a fake-green"`): no seeded runs → assert the report returns `runs: 0` with `nil`/`0.0` metrics and is clearly marked "no data" — it must NOT emit `first_pass_gate_success: 1.0` (a cold-start that *looks* perfect is the vacuity trap). Expected: honest zeros/nils.

> **This task is REPORTED, not gated.** It has **no `--gate`** flag and emits **no blocking scorecard metric.** Its discrimination tests prove the *arithmetic* is right ($0, deterministic, on fixtures); the *live numbers* it produces are informational. This is the explicit boundary: CI proves the query is correct; only a live run produces the numbers, and those numbers never block M4.

**Re-calibration steps:** none. But H6 is where the **provisional §4 targets get recalibrated**: after the live runs, record the *measured* first-pass-gate-success / dispute / parked next to the inherited targets (≥70% / <20% / <15%) and write a one-paragraph "recalibration note" — are the inherited numbers realistic for greenfield Codex, or do they need revising? (ROADMAP §4 explicitly invites this: "recalibrate, do not treat as derived.")

**Green criteria:**
- `MIX_ENV=test mix test --seed 0` incl. `LiveReportTest` green (arithmetic correct on fixtures).
- A real live pass is **not** a CI gate; its evidence is the committed `eval/live/<date>.json` + the recalibration note in `M4-DONE.md` Part B.

**Risks/traps:**
- **Coupling-to-agent-reliability trap (the big one):** the seductive mistake is to promote first-pass-gate-success≥70% to a hard M4 gate. ROADMAP §4 and §M1 are explicit that this is wrong — M4's *honesty* (zero false-pass, abstain fires) is provable; M4's *throughput* (first-pass rate) is stochastic and a function of Codex, not Conveyor. H keeps these on opposite sides of the CI-hard / reported line. **If a reviewer asks "why isn't 70% a gate?" the answer is in §4/§M1: gating a milestone on a stochastic agent is a category error.**
- **Empty-window false-green trap:** an empty DB must report "no data," never `1.0`. (Same class as the gauntlet's "0 mutants → vacuous 0 false-pass" trap.)
- **Dispute-metric honesty trap:** true "material dispute" needs a human review verdict (was the gate *right* to reject?). With golden-oracle samples we can only compute false-reject-vs-golden as a proxy. **Label it a proxy**; do not present the proxy as the human-dispute number.

---

### H7 — Finalize DONE checklist + activate falsifier CI canary (after H2–H6)

**Goal:** close the loop — every Part-A box backed by a real green test/command; the falsifier wired as a CI canary now that activation is real; the DONE.md is the single artifact a zero-context agent runs top-to-bottom to verify M4.

**Changes:**

- Wire `mix conveyor.eval.falsifier --check` into `ci.yml` (a new step after the scorecard gate) and into `M4-DONE.md` A6 — now safe because A–F have activated the real gate (H5's pre-activation guard lifts).
- **FILE the follow-on br issues (concrete ACTIONS, not just prose — each is an actual `br` create with parent/label/body, so the follow-ons exist as tracked work, not a doc bullet):**
  - `br create` — **title:** "Real reviewer producer for `reviewer_aggregation` (required-flip)"; **parent:** `dr1m.E13`; **label:** `reliability,reviewer`; **body:** "Advisory at M4 because a solo width-1 loop has no independent reviewer. Required-flip = an AI-reviewer or a Track-B fleet reviewer producer. Seam: `reviewer_aggregation.ex` `:reviews`/`:reviewer_health`."
  - `br create` — **title:** "Real `build_install` producer (required-flip)"; **parent:** `dr1m.E6`; **label:** `reliability`; **body:** "Advisory at M4 (Python samples have no build step). Required-flip once a buildable sample or the Elixir self-build is in the loop; seam: `build_install.ex` `:build_install_result`/`:build_install_commands`."
  - `br create` — **title:** "Real deterministic CodeScent adapter for `code_quality_delta` (required-flip; replaces the cut F5 fixture-oracle)"; **parent:** `dr1m.E10`; **label:** `reliability,quality`; **body:** "F5's fixture-tuned regex was CUT (Open Decision 17). Required-flip = a genuine deterministic CodeScent adapter contract satisfying `gate_blocking_contract?/1`; then `new_codescent_high_risk` becomes a real hard catch."
  - `br create` — **title:** "Admit decorative integrity probes (`required_artifacts`, `falsifier_preservation`, `falsifier_survival`) to live `required_probes`"; **parent:** `dr1m.1`; **label:** `reliability,integrity`; **body:** "C3/C4 built + proved these producers via static trip cases but did NOT admit them live (decorative on the reference — F23). Admit once the loop supplies a real non-empty required-artifact set and real falsifier seeds for the reference."
  - `br create` — **title:** "Public-repo reverted-bug-fix external falsifier (higher-realism, non-sterile)"; **parent:** the deferred Verifier-as-product backlog; **label:** `eval,falsifier`; **body:** "H5 ships the sterile in-repo `falsifier/` set (4 fixed targets). The public-repo reverted-bug-fix arm is a post-M4 realism follow-on (needs network/checkout infra; brownfield, out of §4 serial bar)."
  - `br create` — **title:** "`RunGateCanary` repair-or-retire"; **parent:** `dr1m.E14`; **label:** `reliability`; **body:** "It is a second looks-wired-but-vacuous static-discrimination harness (patch_set has no `changed_files`). Repair or retire so it doesn't become a false-confidence harness now that the real `MutantContext` assembler exists."
  - (If G2 deferred per Open Decision 13) `br create` — **title:** "dr1m.8 dedupe-safe artifact-projection migration (ship when a durable DB lands)"; **parent:** `dr1m`; **label:** `data-integrity`; **body:** "The forward-only dedupe-safe migration + dedupe-safe `down` from G2, deferred because Conveyor is Sandbox-only for M4. Ship + test against populated data when a durable run-history DB is introduced."
- Set the `catch_rate` floor and the falsifier `false_accept_rate` target (0, blocking) from the first real activated run; record the numbers in `M4-COST.md`.
- Final pass: run the **entire** Part-A command list, confirm each exits as documented, tick every box. Append the live-measured Part-B numbers + recalibration note.
- **Meta-test** `test/conveyor/m4_done_checklist_test.exs` — `Conveyor.M4DoneChecklistTest`: parse `docs/5_milestones/M4-DONE.md`, assert **every Part-A line has a backing test module that exists and is referenced**, and (optionally) that no Part-A box is left as a bare prose claim without a `$ command`/`backed by:` line. This is the anti-theater guard for the checklist itself.

**Discrimination test(s):**
- **GOOD:** `M4DoneChecklistTest` passes when every Part-A item names a real, existing test module / command.
- **BROKEN:** add a Part-A item with no backing → test fails (proves the checklist can't drift into unbacked claims).

**Green criteria — the full M4 CI-hard gate, all of which a zero-context agent can run:**
```
MIX_ENV=test mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test --include eval --seed 0          # all A–F + H discrimination tests
MIX_ENV=test mix conveyor.eval.rung0                    # emits full-corpus gauntlet inputs
MIX_ENV=test mix conveyor.eval.replay --all            # replay_divergence/fidelity
MIX_ENV=test mix conveyor.eval.falsifier --check       # external falsifier canary (post-activation)
MIX_ENV=test mix conveyor.eval.scorecard --gate ; echo $?   # MUST print 0
MIX_ENV=test mix credo --strict
MIX_ENV=test mix dialyzer
```
All exit 0 ⇒ Part A complete ⇒ **M4 CI-hard exit met.** Part B (live) is then run per `M4-LIVE-PROTOCOL.md` and recorded — informational.

**Risks/traps:** the only way H7 lies is if a Part-A command exits 0 *vacuously* (e.g. the scorecard gate is green because no gauntlet input was emitted). The meta-test + H2's negative-control + H5's benign-control are the three guards that make "green" mean "actually discriminates." Carry forward: **a green gate that ran nothing is the original sin this whole milestone exists to kill** (the retired empty-`[]` `conveyor.gate_canary` footgun, ROADMAP §M0 [w49f]). H7 must assert the gate *ran the corpus* (non-empty `cases`), not merely that it returned healthy.

---

### Cost estimate & budget note (owned by H, lands in `M4-COST.md`)

**CI-hard part: marginal $0.** Every Part-A gate is deterministic, DB-free-or-fixture-backed, and **invokes no LLM** (the gauntlet runs *pytest*, not Codex; the falsifier applies *patches*, not agents; the scorecard is pure aggregation). So the entire hard exit costs **$0 in metered API** and runs in CI for free. This is the leverage: the honesty bar is provable without burning tokens.

**Live part: bounded, on Robert's $200 Codex subscription (marginal $0 metered, but token-budgeted).**
- Baseline from the seed (verified plausible against PR #17 token persistence): **~570k tokens/slice**.
- beads_insight ≈ 7 slices, gx ≈ 7 slices. Per full run ≈ `7 × 570k ≈ 4.0M tokens`.
- Protocol run set = 3 beads + 2 gx = **5 runs** ≈ `5 × 4.0M ≈ 20M tokens`. (The seed's "~13.7M / ~$18.57 for a 7-slice plan" implies ~1.96M/slice *list-price* equivalent; using that, 5 runs ≈ **~68M token-equivalents ≈ ~$92 EST list-price**, but **marginal $0** on the $200 subscription since it's flat-rate.)
- **Recommendation:** report **both** a token total and a *list-price-equivalent $* (so cost-per-verified-outcome stays a real metric per HUMAN.md), while noting the **actual marginal spend is $0** on the subscription. Set a **dev-phase not-to-exceed of 10 live runs / ~150M token-equivalents for M4 validation** (ROADMAP §6 asks for exactly this NTE before repeated live runs); if a run set blows past it (e.g. heavy rework loops), pause and report rather than silently burning the subscription's fair-use headroom.
- **Lift duel arm** reuses the committed `eval/lift/seed.json` where possible to avoid re-running the vanilla arm live → keeps the lift measurement near-$0.

> **Cost honesty:** the seed's "$18.57 for 7-slice" and "570k tok/slice" are *baseline estimates from one prior run*, not measured M4 numbers. H6's `LiveReport` task emits the **real** `tokens_total`/`cost_estimate_total` from `agent_session`, which H7 records as the *actual* M4 cost — replacing the estimate. Do not present the estimate as measured.

---

### Mapping each exit item to the ROADMAP §4 exit bar (the contract)

| §4 bar item | M4 owns? | H proves it as… | CI-hard or live? |
|---|---|---|---|
| **Gate honesty** — MutantGauntlet full-corpus **zero false-pass** in CI (gated by `scorecard --gate`); integrity-discrimination in CI | **Yes (M4)** | H2 full-corpus gate + H3/H4 integrity-discrimination | **CI-HARD** |
| **Abstain fires for real** | **Yes (M4)** | H4 end-to-end abstain from a real broken producer signal (persisted `:abstained`/`:parked`) | **CI-HARD** |
| **First-pass gate success ≥70%** (provisional, inherited) | Measured at M4 | H6 `LiveReport` first_pass_gate_success + recalibration note | **LIVE / reported** |
| **Material-dispute <20%** (provisional) | Measured at M4 | H6 false-reject-vs-golden proxy scoped to LIVE Codex rejections only (NOT the reference) + honesty caveat | **LIVE / reported (proxy, live-Codex-only)** |
| **Parked-rate <15%** (provisional) | Measured at M4 | H6 parked-rate from `ParkedQueue.abstained/0` over the run window | **LIVE / reported** |
| **Demonstrated lift** (defects-caught/honest-abstention vs bare agent) | Measurable only post-M4 | H6 lift arm + H5 falsifier catch-rate | **LIVE / reported (+ falsifier CI canary)** |
| **Hermeticity** (D1.2: missing → abstain more, never false-pass) | Wanted at M4 | H1 A5 + C's docker-absent-abstains test (H asserts it's in the checklist) | **CI-HARD (honesty axis)** |
| Joined seam / decomposition-in-loop / unattended medium plan / survivability | **NOT M4** (M1/M5/M6) | H explicitly records these as **out of M4 scope** in DONE.md so the bar isn't falsely claimed | n/a |

> The last row is load-bearing honesty: §4 is the *whole serial bar*; **M4 satisfies a subset.** H's DONE.md states plainly which §4 items M4 closes and which remain for M5/M6 — so "M4 done" is never misread as "§4 bar met."

---

### Open question for Robert (kept minimal — one genuine fork)

**Dispute-rate definition.** True "material-dispute <20%" needs a human verdict on whether the gate was *right* to reject (a parked-queue review loop). On the golden-oracle greenfield samples, H6 can only compute **false-reject-vs-golden** as a proxy. Recommendation: ship the proxy for M4 (labeled as such) and defer the real human-dispute metric to the parked-queue review loop (a Track-B / fleet concern, same place the real reviewer producer lives). **Confirm:** proxy-for-M4 + defer-real-dispute, or do you want a lightweight manual review pass on the ~5 live runs to get a true (tiny-N) dispute number? (My pick: the proxy — a 5-run manual dispute count is too small-N to be more honest than the deterministic golden proxy.)

---

## 9. Cross-cutting — the TrustScore re-calibration protocol

This consolidates how weights/threshold are re-tuned against the green reference as producers land. It is owned by sub-stream A (A6) and referenced by B, C, D; it is reproduced here as the single cross-cutting rule because the temptation to "rescue a parked reference by lowering the bar" is the most dangerous failure mode in M4.

**The headline fact (verified by arithmetic, weights 0.30/0.20/0.20/0.15/0.15, threshold 0.9):** the known-good reference scores **0.925 at every M4 stage** and never needs a re-tune. The laundered-but-not-yet-real signals (integrity, replay, corpus) keep their good/0.5 tokens until B/C/D flip them; each flip lands paired with its real producer supplying the genuine good token, so the score does not move. **No A, B, C, or D slice requires a weight or threshold change.** The re-tune machinery exists as a safety rail, not because any M4 slice is expected to use it.

> **⚠ CAVEAT (surfaced in review — the headline has a hidden dependency on replay laundering):** the "0.925 at every stage / no re-tune" fact relies on **replay being laundered to the GOOD token (`:none`, 1.0) on cold start**, NOT scored as the not-assessable middle (0.5). On a fresh checkout (every CI run) B1's per-checkout `BaselineStore` is empty → every slice is a "first observation" → `:none` (1.0) *by construction* (no persisted baseline to diverge from). If replay were treated taxonomy-honestly (no baseline ⇒ not-assessable ⇒ 0.5, exactly like corpus), cold-start would be `0.30 + 0.20 + 0.20 + 0.15·0.5 + 0.15·0.5 = 0.85 < 0.9` → the reference would PARK, forcing a real re-tune. So "no re-tune needed" is true ONLY because cold-start replay is laundered. Treat `replay earned?` like the F13 `integrity earned?` flag (it is NOT earned on a cold start); see the REPLAY EARNED note below, B1's fingerprint-surface risk bullet, and **Open Decision 19**.

The anchor table (the `reference_auto_accept_test.exs` invariant). **The `integrity earned?` column is the F13 honesty flag — see the note below the table:**

| M4 stage | integrity | calibration | baseline | replay | corpus | score | band | **integrity earned?** |
|---|---|---|---|---|---|---|---|---|
| Today (all laundered) | trustworthy 1.0 | valid 1.0 | green 1.0 | none 1.0 | nil→0.5 | **0.925** | auto_accept | **no (laundered/fabricated)** |
| After A2/A3 (baseline real) | 1.0 | 1.0 | 1.0 (real) | 1.0 | 0.5 | **0.925** | auto_accept | **no (still laundered)** |
| After A4/A5 (calibration real) | 1.0 | 1.0 (real) | 1.0 | 1.0 | 0.5 | **0.925** | auto_accept | **no (still laundered)** |
| After B (replay per-slice producer wired; corpus floored) | 1.0 | 1.0 | 1.0 | 1.0 (real ONLY w/ persisted baseline; **cold-start laundered†**) | 0.5 | **0.925** | auto_accept | **no (still laundered)** |
| After M4.7 (D1/D2/D3 docker foundation; integrity STILL laundered) | 1.0 (laundered) | 1.0 | 1.0 | 1.0 | 0.5 | **0.925** | auto_accept | **no (still laundered)** |
| **At M4.8 {D4 + C1} ATOMIC** (un-launder + admit mount_boundary) | 1.0 (real) | 1.0 | 1.0 | 1.0 | 0.5 | **0.925** | auto_accept | **YES (earned @ D4+C1)** |
| After M4.8b (C2 mapping admitted; C3/C4 built-not-admitted; D5–D7) | 1.0 (real) | 1.0 | 1.0 | 1.0 | 0.5 | **0.925** | auto_accept | **yes** |

**F13 HONESTY NOTE (integrity earned column):** through the EARLY window (M4.1 → M4.7, i.e. everything before the atomic M4.8) the reference's integrity `1.0` is **LAUNDERED/fabricated — NOT earned.** An auto-accept in that window proves **calibration / baseline / replay are real**, NOT integrity — the 0.925 includes a fabricated `0.30·1.0` integrity contribution until D4. A reviewer must NOT misread an early-window green reference as a fully-real one. **Integrity becomes EARNED only at the atomic M4.8 {D4 + C1}** — when un-laundering and the first clean `mount_boundary`/`source_mutation` admission co-ship. The `reference_auto_accept_test.exs` anchor (A6) carries this per-stage `integrity earned? no/no/…/yes(@M4.8)` flag so the executor cannot misread a laundered-integrity green as a real one.

**† REPLAY EARNED note (the analogue of F13 for the `replay` column — surfaced in review):** the reference's replay `:none` (1.0) in EVERY row above is **laundered, not earned, on a cold start — and CI is always a cold start.** B1's `BaselineStore` is per-checkout and empty on a fresh clone, so every slice is a "first observation" → `:none` *by construction* (no persisted baseline to diverge from), never a *measured* `:none`. Replay can only EARN `:none` (or fire `:diverged`) when a persisted baseline EXISTS to compare against (the live cross-run path on a durable box); even then the whitelisted surface (`baseline_health_status`/`test_pack_calibration`/`integrity_verdict` — all base-relative or process-level) diverges only on FLAKY scaffolding, never on a divergent agent patch (patch + `verification_result` excluded by design). So an auto-accept in any row above does NOT prove replay reproducibility was measured. Carry a `replay earned? no (cold-start) / yes (only w/ persisted baseline)` flag alongside `integrity earned?`, and resolve **Open Decision 19** (store persistence + whether replay should be a HARD `trustworthy?` gate at all on the cold-start/CI backend, or a not-assessable boost like corpus). **Load-bearing consequence:** the "0.925 / no re-tune" headline holds ONLY because cold-start replay is laundered to 1.0; an honest not-assessable 0.5 makes cold-start `0.85 < 0.9` → park → forced re-tune.

**The danger window (the one interlock — RESOLVED by the atomic co-ship):** if D4's un-laundering of `not_assessed` landed in a SEPARATE commit from C1's first real clean probe admission, the reference integrity would momentarily be a genuine `not_assessed` (0.5) → score 0.775 → park. This is why **D4 + C1's first admission CO-SHIP in ONE ATOMIC commit** (M4.8). At no committed point does the reference sit at 0.775 — the 0.925 → [transient] → 0.925 transition is never committed mid-state.

**The re-tune decision rule (the brake), applied in order:**
1. Compute the reference score at the new stage. If ≥ 0.9 → **no re-tune.** (Every M4 stage is 0.925.)
2. If a flip drops the reference below 0.9, FIRST ask: *did a real producer return a non-good token for the reference?* If yes → that is a real defect (corpus or producer bug) → **fix it, do not re-tune.**
3. Only if the reference's tokens are all genuinely good but the *score* fell purely because a newly-real not-assessable-on-backend signal scores 0.5 → re-tune by reducing that signal's weight (redistributing to measured signals) OR lowering the threshold to the new reference floor minus epsilon, whichever is more honest. **Record before/after in the PR body and update the anchor test.** Re-run all three corpora end-to-end.
4. **FORBIDDEN:** lowering the threshold below the level at which a known mutant would auto-accept. **The hard interlock:** after any threshold/weight change, re-run the gauntlet and assert `false_pass_rate == 0`. If a re-tune lets a mutant through, the re-tune is invalid and fails CI.

**Mechanical enforcement (H3):** a single guarded `TrustScoreCalibrationTest` lives in the **default** suite (not `:eval`), so any A–F weight/threshold change that would park the known-good reference breaks the base suite immediately. The `policy_digest` is pinned to a constant that must be updated in the same commit as any weight change — making every calibration change reviewable in the diff. The golden reference evidence must equal the *real* output of the producers (cross-checked in H4 against a live clean beads_insight run), not a hand-rigged all-good map, or the guard green-washes.

---

## 10. Exit & validation (sub-stream H, summarized)

The full detail is in Section 8's H sub-stream. The contract, in brief:

**Everything provable for $0 deterministically in CI is a HARD gate; everything that depends on a stochastic live Codex agent is REPORTED, never a hard gate.** (ROADMAP §4 and §M1 both warn that coupling a milestone exit to agent reliability is a category error.)

**Part A — CI-HARD ($0, deterministic; these BLOCK M4):**
- A1: Full-corpus zero false-pass — `mix conveyor.eval.scorecard --gate` exits 0 over the FULL behavioral+static corpus across all samples (H2 fixes the `@suite` collision so the three samples don't overwrite one scorecard input).
- A2: Every A–F discrimination test green — `mix test --include eval --seed 0` exits 0.
- A3: Abstain fires end-to-end on a REAL broken signal (H4) — through the production Finalizer, asserted from PERSISTED `run_attempt.outcome == :abstained` + `slice.state == :parked`, not injected synthetic evidence.
- A4: Re-calibration regression — the known-good reference still auto-accepts at the shipped weights/threshold (H3).
- A5: Hermeticity-absent abstains (not false-passes) — docker-absent → `not_assessed` → non-blocking park, $0 (D2/C/F7).
- A6: External-falsifier probe catches planted defects — `mix conveyor.eval.falsifier --check` exits 0 (H5; sterile in-repo sample mutants run through the FULL activated gate; the public-repo reverted-bug-fix variant is a flagged post-M4 follow-on, NOT M4-blocking).

**Part B — LIVE-MEASURED (stochastic; REPORTED, does NOT block M4):**
- B1: first-pass-gate-success measured on beads_insight + gx (target ≥70% PROVISIONAL).
- B2: material-dispute-rate measured (target <20% PROVISIONAL) — computed as a false-reject-vs-golden PROXY, honestly labeled; the true human-dispute metric is deferred to the parked-queue review loop (Track-B).
- B3: parked-rate measured (target <15% PROVISIONAL).
- B4: demonstrated lift on defects-caught/honest-abstention vs. a bare agent.

**Run set:** 5 runs (3 beads_insight + 2 gx), reported never gated. 5 is enough to MEASURE a rate, deliberately not the §4 "5 consecutive green ≥20-slice" bar (that is M6).

**Cost:** the CI-hard part is marginal **$0** (no LLM — the gauntlet runs pytest, the falsifier applies patches, the scorecard aggregates). The live part is bounded with a dev-phase not-to-exceed of ~10 runs / ~150M token-equivalents; the `LiveReport` task emits real `agent_session.tokens`/`cost_estimate` so the reported cost is measured, not estimated. Report both the token total and the list-price-equivalent $, while noting the actual marginal spend is $0 on the $200 subscription.

**Honesty fence:** M4 satisfies a SUBSET of the §4 serial bar (gate honesty + abstain-fires + hermeticity + measured first-pass/dispute/parked). The joined-seam / decomposition-in-loop / unattended-medium-plan / survivability items are M1/M5/M6 and are stated plainly as out-of-M4-scope in `M4-DONE.md`, so "M4 done" is never misread as "§4 bar met."

---

## 11. Risk register & brake-on-complexity

Consolidated from every sub-stream's `risks_flagged` + the looks-wired-but-vacuous traps + the largest/riskiest slices. Read as a skeptic.

### The looks-wired-but-vacuous traps (the worst kind of false confidence)

1. **`VerificationRerunner` inherits the empty-acceptance-suite leak (dr1m.7).** The seed facts named only `ToolchainRunner.suite/3` and the `test_execution` gate stage — but the PRODUCTION path uses `VerificationRerunner` (`test_execution.ex:48`), which has the identical `Enum.all?([], …) == true` leak. Fixing only the two named spots makes the gauntlet (CI) green while production still false-passes. **A7d fixes all three layers.** This is the canonical "CI goes green, production stays leaky" trap.

2. **`RunGateCanary` looks like static discrimination but is vacuous.** Its `patch_set` carries only `id`/`patch_ref`/`expected_catch` — NO `changed_files` — so every static stage (`ContractLock.protected_path_findings`, `PolicyCompliance.policy_file_findings`) sees an empty list and passes; its tests use a stub `FixtureGateStage`. Sub-stream F does NOT extend it (it builds the real `MutantContext`); the DECOUPLING tests in F2–F5 are the antidote. **Flag for E:** `RunGateCanary` should be repaired or retired so it doesn't become a second false-confidence harness.

3. **`trust_score_test.exs:55-65` ("thin/not_assessed abstains") is vacuous in production.** It feeds the scorer a hand-built `not_assessed` map the assembler never produces (because `trust_evidence.ex` launders first). It passes while the real path it's supposed to protect is broken. A1 makes the path reachable; A7's `band_of_output` mandates that every discrimination test go through `from_run_output`, not a hand-built map.

4. **A discrimination test that only asserts the green direction (or only `refute gate.passed?`).** A stage can reject the known-good by accident and "pass" a `refute passed?` test while being a false positive. Every required-flip needs BOTH the GOOD half (real reference → accepts, no false-park) and the BROKEN half asserting the EXACT `expected_catch.category`/`rule_key`. The `full_gate_fixture/1` helper (E9) is itself a vacuity surface — if it doesn't mirror production `default_gate_context/3` field-by-field, all GOOD-half tests pass against a fiction; E9 cross-checks it with a real-SerialDriver production-path proof.

5. **A skipped-everywhere docker test + no enforced metric = "zero false-pass in CI" vacuously true.** D7's mitigation is mandatory: a docker-enabled CI job MUST run the discrimination test on the M4-exit branch, AND the `hermetic_false_pass_rate` metric MUST be emitted by a real run (not a static fixture). A green gate that ran nothing is the original sin this milestone exists to kill.

6. **The "rejects everything looks like 100% catch" trap (H5).** A falsifier probe that abstains on everything (e.g. because hermeticity is `not_assessed` and everything parks) shows catch-rate 1.0 vacuously. The benign negative control (a clean patch MUST auto-accept) is non-negotiable.

7. **`caught == not gate_passed` would make `false_pass_rate=0` a lie (F6).** A static mutant rejected for the WRONG reason (a stage fail-closing on a missing input) would count as a catch. The `caught_by_expected?` helper (mirroring `RunGateCanary.expected_match?`) is mandatory — a wrong-reason rejection counts as a false PASS, not a catch.

8. **`gate_code_sha256` was a constant label `digest("gate")` (serial_driver.ex:380)** → a vacuous freshness key (a stale canary from before stages were wired still looks fresh). E7 fixes it to a real `Pipeline.code_sha256/0` digest over the `@full` stage table so wiring changes invalidate stale canary health.

### Correctness traps (subtle, easy to get backwards)

9. **The passed/green vocabulary mismatch (A1).** The baseline station emits `"passed"`/`"failed"` strings; the score's vocabulary is `green`/`red`. The old catch-all routed `"passed"` to `:green` by accident; after A1 stops laundering, `"passed"` must be EXPLICITLY mapped to `:green` or the reference parks — and the tempting wrong "fix" is lowering the threshold, masking the bug.

10. **The `nil` vs unrecognized boundary in `replay/1` (B1).** `nil` (no producer ran) → `:none` (staged-rollout non-blocking default, keeps `assemble(%{})` green); a PRESENT-but-unrecognized value → `:unknown` (fail-closed). Get it backwards and either the staged-rollout default breaks (reference parks) or laundering persists. The two added `trust_evidence_test.exs` assertions pin both sides.

11. **A volatile corpus number could flip a fail-OPEN boost into a fail-CLOSED park (B2) — resolved by the clamp.** Corpus is made STRICTLY boost-only: the auto-accept band uses `max(0.5, corpus_rate)·0.15`, so a low fidelity can never alone drop a `trustworthy?`-passing reference below 0.9 (worst case `0.925`). The raw rate is still recorded/scorecard-tracked. The significance floor (`< 5 cassettes → nil`) is kept only as an observability nicety, no longer load-bearing for never-parking the reference.

12. **The integrity un-laundering must NOT land without a real clean probe (C1/D4 interlock).** Un-laundering `not_assessed` while no probe is admitted drops the reference to 0.775 → park. D4 + C1's first admission co-ship.

13. **`hermeticity` unconditionally in `required_probes` pins `:local` to `not_assessed` forever (C1).** `required_probes` must be backend-dependent (`hermeticity` only under `:docker`), or every probe admission is vacuous on the default `:local` backend.

14. **Calibration must run on the BASE checkout, not the patched tree (A4).** If it runs on the patched tree the tests pass → `:invalid` → reference abstains. **And the deeper risk:** if the reference's locked acceptance tests are NOT genuinely red-on-base, A4 will correctly make the reference abstain — and the tempting "fix" is to revert to fabrication. DO NOT. That means the corpus was vacuous; fix the corpus so its locked tests genuinely assert the slice behavior.

15. **Editing an applied migration desyncs `schema_migrations` (G2).** `20260620110000` is not the latest migration and may already be applied; dr1m.8 MUST be a NEW forward-only migration, never an in-place edit.

16. **Asserting on the in-memory struct instead of a fresh DB re-read (H4, G1).** The in-memory `finalized.run_attempt.outcome` can be right while the DB write silently failed (the dr1m.1.1 class of bug). Always re-read from the DB.

### The largest / riskiest slices (where to slow down)

- **A4 (real AcceptanceCalibration)** — the single most dangerous stub; it fabricates `:valid`. High-value because it reveals whether the reference's acceptance tests were ever meaningful.
- **E (all 14 stages)** — the largest sub-stream, most prone to fail-close-on-missing-input false-parks. **Brake:** 9 required-live + 5 advisory is the honest M4 line (provenance + canary advisory-with-gated-required-flip per Open Decision 16; build_install/code_quality_delta/reviewer advisory). Resist forcing any advisory stage required without its gating verification (real producer + pre-flip audit / conductor hook) — that is the single largest vacuity/blast-radius risk in M4. E6/E7 build + prove their producers but defer the blocking flip; the gate is strictly stronger at every step.
- **D4 (integrity flip)** — the whole-suite triage trap: flipping `integrity(_) -> not_assessed` may red OTHER tests that silently relied on no-integrity-signal auto-accepting. Triage each red (update to docker OR fix a real second vacuity) — never blanket-green them (that re-launders the vacuity in the test layer).
- **F3 (ContractLock synthetic bundle)** — six digest equalities + mount checks must all hold for known_good or the reference parks; the GOOD-signal unit (`findings == []`) is load-bearing.

### Brake-on-complexity decisions (kept lean on purpose)

- **No new TrustPolicy runtime subsystem (A6).** The re-tune protocol is a *process* encoded as the `reference_auto_accept_test` anchor + the gauntlet `false_pass_rate` interlock — weights/threshold stay as existing module attributes + opts overrides.
- **No `unshare -n` (Decision 3).** docker `--network=none` only; the hardened `DockerRunner` lifecycle is NOT used (lighter `ToolchainRunner` docker path).
- **`corpus_pass_rate` clamp (`max(0.5, rate)`) over weight-churn (B2).** Makes corpus strictly boost-only by arithmetic (it can never alone park a trustworthy run) instead of re-weighting; the significance floor is kept only for observability.
- **`required_artifacts` scoped to verify-stage artifacts (C3), not duplicating RunCheck.** Brake on cross-stream double-implementation (`mapping` overlaps E's AcceptanceMapping; `required_artifacts` overlaps RunCheck — consume the canonical source).
- **tasks_service-only static corpus for M4 (F8).** One fully-discriminated sample proves the harness; cross-sample static mutants are a post-E fast-follow.
- **`code_quality_delta` fixture-oracle CUT (F5).** The fixture-tuned-regex hard catch is removed from the M4 gauntlet — it was a reverse-engineered oracle (catches exactly one mutant by construction) for a stage that is advisory in the live gate anyway. `code_quality_delta` stays wired-but-advisory (Decision 1 honored: advisory wiring is wiring); `new_codescent_high_risk` is advisory in BOTH gauntlet and live gate; a real deterministic CodeScent adapter is a Track-B follow-on. The gauntlet's anti-vacuity value comes from the 4 real-producer stages.
- **G2 reversibility over irreversibility.** ~10 lines for a dedup-safe `down` beats a permanent one-way door.

### Scope & trust-boundary oversights (surfaced in adversarial review)

- **The coding agent runs on the HOST, not in a container — M4 hardens the JUDGE, not the producer's sandbox.** The implement station drives Codex via `System.cmd … --sandbox workspace-write` on the host (`lib/conveyor/agent_runner/codex.ex`); the `docker --network=none` hermetic backend (sub-stream D) isolates only the *gate's verification rerun*, NOT the agent. So a prompt-injectable, stochastic agent has host write/exec/network access during implementation, while M4's whole thrust is hardening the *downstream verifier*. The plan never names this residual blast radius. **Action (honesty, not a functional M4 defect):** (a) add an explicit line to `M4-DONE.md` — "M4 hardens the judge; sandboxing the producer (agent host execution) is OUT of M4 scope"; (b) file a tracked follow-on and link the ROADMAP M6 item "agent runs inside the M4 container"; (c) do NOT let "hermetic gate" be read as "hermetic agent."
- **E9's "real-SerialDriver production-path proof" is a named green criterion but is never instantiated as a concrete test.** §7 (M4.10) and the E9 slice both promise an accept proof on the REAL driver path, yet E9's three enumerated tests all build context via `full_gate_fixture/1`, and `default_gate_context/3` is `defp` with no test seam. **Fix:** pin a named E9 test that runs the real `SerialDriver` path over the reference and asserts `outcome == :accepted` AND that persisted `GateResult.stages` reflect all 9 wired stages — else the GOOD-half is proven only against a fixture the production loop may never reproduce (risk #2's own warning, applied to E9).

---

## 12. br issue plan

### Issues CLOSED by M4 (union of `br_closed` across sub-streams)

| br id | Closed by | What it is |
|---|---|---|
| `dr1m.1.3` | A2+A3 (baseline), A4+A5 (calibration) | BaselineHealth + AcceptanceCalibration vacuous stubs |
| `dr1m.7` | A7d; co-verified by H4/H2 | acceptance_locked passes vacuously on zero tests → silent false-PASS (fixed at THREE layers) |
| `dr1m.1.4` | B1 (gate half) + B3 (report-field half) | hardcoded `replay_fidelity = "matched"`; unfed `replay_divergence`/`corpus_pass_rate` keys |
| `software-factory-ai-dr1m.1` (producer-side, partial) | C0–C5 | IntegritySentinel dormant probe producers (ADR-23 deferred pass) |
| `C-integrity.0..5` | C0–C5 (create as children of dr1m.1) | per-probe producer + admission + discrimination |
| `8hx7` | D5 (+ moot under docker via D3) | gate pytest venv resolved from the wrong sample |
| integrity/hermeticity half of `dr1m.1` / `dr1m.1.3` | D4 | integrity verdict becomes a live, fail-closed signal |
| `dr1m.E1, .E3, .E4, .E5, .E8, .E11` (required-live); `.E6, .E10, .E12, .E13, .E14` (ADVISORY at M4; required-flips gated/deferred — Open Decisions 16/17) | E0–E10 (create as children of dr1m) | wire all 14 stages (9 required-live + 5 advisory) + reachable failure branches + provenance/canary producers built+discriminating |
| `br-m4-mg-001..012` (placeholders — confirm/create real ids) | F1–F8 | MutantGauntlet static-stage extension |
| `dr1m.1.2` | G1 | duplicate CodeProvenanceEdge on re-finalization |
| `dr1m.8` | G2 | unsafe artifact-projection migration on populated DB |

> **br id caveats:** the `dr1m.E*` ids (E sub-stream) and `C-integrity.*` ids (C) are proposed children of epic `dr1m`; create them with the given slugs. The `br-m4-mg-*` ids (F) are placeholders — confirm or create the real MutantGauntlet-static backlog ids (the seed `dr1m.*` ids belong to other sub-streams). H opens a tracking umbrella `m4.exit`.

### NEW issues to FILE (from `open_for_robert` + deferred items)

- **Real reviewer producer (Decision 4 / E8 / dr1m.E13).** `reviewer_aggregation` is advisory at M4; file a Track-B/fleet or AI-reviewer follow-on — independent reviews do not fit a solo width-1 loop.
- **Real build_install producer (E8 / dr1m.E6).** Required-flip once a buildable sample (or the Elixir self-build) is in the loop.
- **Real deterministic CodeScent adapter (E8 / F5 / dr1m.E10).** Required-flip = a genuine adapter contract; the `new_codescent_high_risk` canary becomes a hard catch then.
- **Genome historical-rate upgrade for `corpus_pass_rate` (B4).** Swap `CorpusPassRate.read/1`'s source from cassette-fidelity (a reproducibility proxy) to the Genome's labeled historical pass rate once outcomes accrue; the `float()|nil` contract is source-agnostic so it's a one-module swap.
- **Repo-source prompt-injection scanning (E5 / F4).** `repo_prompt_injection_ignored` is REROUTED to `run_check`/`untrusted_instruction_followed` for M4 (F4 verified catchable). A broader repo-source prose injection scanner (beyond artifact-content markers) is a follow-on.
- **Public-repo reverted-bug-fix falsifier (H5).** The higher-realism, non-sterile external falsifier is a post-M4 follow-on under the deferred Verifier-as-product backlog.
- **`RunGateCanary` repair-or-retire (F risk #1).** It is a second looks-wired-but-vacuous static-discrimination harness; flag for E to repair or retire.
- **Per-project runner image registry (D3 / D9).** D3 threads an explicit `docker_image` opt (default pinned ghcr image); a `Project.runner_image` field is a follow-on.
- **True human-dispute metric via parked-queue review loop (H6).** M4 ships the false-reject-vs-golden proxy; the real metric is a Track-B/fleet concern.

---

## 13. Open decisions for Robert

Deduped union of every sub-stream's `open_for_robert`, each with the recommendation. Kept minimal — most are "I baked X; confirm or override."

1. **Baseline-empty policy (A2).** I baked: a slice with zero `baseline_regression` suites → `:unknown` → abstain (fail-closed *park* for a human). **Recommend** this conservative, taxonomy-consistent default vs. treating no-baseline as non-blocking. *Confirm or override.*

2. **No content-addressed policy file/loader now (A6).** I baked: keep weights/threshold as module attributes + opts overrides; the re-tune protocol is a process (the anchor test + the gauntlet interlock), not a new runtime subsystem. **Recommend** deferring a policy-loader (the `policy_digest` field already content-addresses the in-memory weights). *Confirm.*

3. **`corpus_pass_rate` significance-floor N (B2).** I chose N=5 cassettes for "statistically meaningful boost." **Recommend** keeping it (or making it config-driven); the `read/1 -> float()|nil` contract is unaffected either way. *Name a preferred minimum if you have one.*

4. **Replay baseline store path (B1) — DEFAULT CORRECTED OFF `priv/`.** Now defaults to the writable, per-checkout `.conveyor/replay_baselines/<contract_sha256>/<slice_id>.json` (or a configured data dir), with a guard that an unwritable/missing store RAISES rather than silently returning `:none`. The old `priv/` default was wrong (read-only in releases → silent always-`:none` regression). *Confirm the writable-path default, or name a configured data dir; the behaviour is injectable regardless.*

5. **gx static mutants (B1 / F8 / H2).** gx has no `mutants.json`. **Recommend** M4 ships static discrimination on tasks_service only (one fully-discriminated sample proves the harness), with beads behavioral-only and gx as a known-good auto-accept reference; cross-sample static mutants are a post-E fast-follow. *Confirm — OR decide gx must contribute behavioral mutants to the corpus before M4 exit (else the "full canary corpus" claim is scoped in writing to two of three samples).*

6. **`mount_boundary` honest-on-`:local` definition (C1).** I chose "writes to declared locked/protected paths during the run" (measurable on `:local`) vs. deferring `mount_boundary` entirely to docker. **Recommend** the locked-path definition (a real backend-agnostic integrity signal, cheap win). *Confirm or push fully to D.*

7. **C5 re-tune posture (C5).** Predicted to be a no-op (reference stays 0.925 ≥ 0.9). **Recommend** keeping `auto_accept: 0.9`. *If you want a STRICTER posture (raise the threshold to force more parking / earn autonomy slower), say so and I'll design the stricter threshold + matching re-tune table.*

8. **Conductor passes `hermetic_gate: true` (D3).** **Recommend YES** — the production conductor's real `assemble!` call site sets `hermetic_gate: true` (the conductor runs hermetically); tests stay false. *Confirm the exact conductor entry point to set it on.*

9. **Docker-absent policy (D2).** **Recommend** still running the `:local` suite (so the gate can REJECT a broken patch) but forcing `not_assessed` so it can never ACCEPT — vs. refusing to run verification at all. *Confirm.*

10. **Hermetic-gate CI (D7) — RESOLVED in-plan (Decision 10 settled).** Default shipped: a SEPARATE required-for-merge `hermetic-gate` docker job (`ubuntu-latest`, host docker daemon, `mix test --only docker`, emits `hermetic_false_pass_rate` from a REAL docker run with a non-empty-case-set meta-assertion). *Confirm the job structure (separate vs. docker-in-main) and required-for-merge — but the plan no longer defers this; the concrete job spec is in D7.*

11. **E8 advisory disposition (E8).** **Recommend** `build_install`/`code_quality_delta`/`reviewer_aggregation` stay advisory (`required?: false`) at M4 with flagged Track-B producers — a solo width-1 loop has no real producer for any. (Plus `provenance_attestation` + `canary_freshness` advisory-with-gated-required-flip per Open Decision 16.) *Confirm you accept the cheap static stages (1,3,4,8,11 + already-live 2,5,7,9) required at M4 exit, with provenance/canary/build_install/code_quality_delta/reviewer advisory, rather than chasing all 14 required.*

12. **`repo_prompt_injection_ignored` canary (E5 / F4) — DEFAULT now REROUTE (F4 verified it catchable).** F4 verified the README marker "ignore the locked contract" is in `run_check`'s `@injection_markers` and fires `untrusted_instruction_followed` when the README is fed as artifact content. **Recommend re-pointing** `expected_catch.stage → run_check`, `category → untrusted_instruction_followed` (F4 owns the manifest edit). Fallback: disable with a Track-B "repo-source injection scanning" follow-on IF the prose does not reach a gate-visible artifact. *Confirm reroute (default) vs. disable.*

13. **`dr1m.8` / G2 urgency — GATES whether G2 is in M4 (G2 is CONDITIONAL, not mandatory; this SOFTENS Decision 1's blanket inclusion of dr1m.8). Robert can keep it mandatory.** Is a durable, populated, non-Sandbox `Conveyor.Repo` DB in scope before M4 ships? `config/dev.exs` (pool_size 10) + `config/runtime.exs` suggest it's anticipated. **Default (recommended): make G2 conditional on this answer.** If Conveyor stays Sandbox/ephemeral for all of M4 (the likely answer given Sandbox-only CI), dr1m.8 cannot manifest and G2's test exercises only a scratch table — **DEFER G2** to the milestone that introduces the durable DB, filed as a tracked follow-on, and do NOT spend an M4 slice on it. If a durable run-history DB IS planned before M4 ships, G2 is load-bearing and ships in M4 + is tested against populated data. **G1 stays in M4 regardless** (it is genuinely triggered by M4's re-run/replay loop). *Decide scope — this trims one latent-bug slice with a scratch-table-only test from the M4 critical path; restore G2-mandatory if you want dr1m.8 shipped in M4 regardless.*

14. **`dr1m.1.2` edge-identity scope (G1).** **Recommend** dropping `run_attempt_id` from the digest (so deterministic re-runs/replays producing identical patches dedupe to ONE edge — replay-first). *Flag if you want attempt-scoped provenance (one edge row per attempt even for identical patches) — the discrimination test setup changes accordingly.*

15. **Dispute-rate definition (H6).** **Recommend** shipping the deterministic false-reject-vs-golden PROXY for M4 (labeled as a proxy) and deferring the true human-dispute metric to the parked-queue review loop — a 5-run manual count is too small-N to beat the golden proxy. *Confirm proxy-for-M4 + defer-real-dispute.*

16. **`provenance_attestation` + `canary_freshness` required-vs-advisory at M4 exit (E6/E7) — SOFTENS the "required" wording of Decision 4. Robert can restore the stricter posture.** **Default shipped (recommended): ADVISORY at M4 with a GATED required-flip.** We honor Decision 4's "build REAL producers" in full — both producers are built and proven to DISCRIMINATE (the BROKEN-half tests land) — but at M4 exit they are wired `required?: false` rather than HARD auto-accept gates, because a required provenance false-parks the reference on any one of ~8 missing/nondeterministic digests, and a required canary parks every slice on `stale_canary` until `RunGateCanary` is wired into the conductor (arguably M5/M6 conductor work). The required-flip is **gated**: provenance→required needs the pre-flip digest audit (every required digest recorded for beads/gx/tasks) green; canary→required needs the `ensure_fresh_canary!` conductor pre-slice step writing a fresh `GateHealth` row for the current freshness key before each slice. If a precondition is unmet at M4 exit, that stage's required-flip SLIPS to early M5 (filed as a tracked follow-on). This removes the "one missing digest / unwired conductor parks every run" risk from the M4 exit bar while keeping the gate strictly stronger (findings visible, discrimination proven). *Confirm advisory-with-gated-required-flip — OR restore `required`-at-M4 for either/both if you want the stricter exit AND accept the producer/conductor build risk inside M4 (then E6/E7 flip `false → true` and the pre-flip verifications must pass before M4 exit).*

17. **`code_quality_delta` fixture-oracle CUT from the M4 gauntlet (F5) — SOFTENS Decision 1's "wire all 14 / MutantGauntlet static-stage extension" for this one stage. Robert can restore the hard catch.** **Default shipped (recommended): CUT the fixture-tuned-regex hard catch.** The original F5 manufactured a `code_quality_delta` hard catch by injecting a `code_quality_run` whose `new_high_risk_findings` came from a test-authored regex tuned to score exactly the one planted `new_codescent_high_risk` mutant — a reverse-engineered fixture oracle (catches that mutant by construction, nothing else), for a stage that is ADVISORY in the live gate (E8) anyway. Decision 1's "wire all 14" is still honored — `code_quality_delta` IS wired (advisory; advisory wiring is wiring) — we simply do not add a fixture-oracle HARD catch. `new_codescent_high_risk` becomes `archetype: advisory` (advisory in BOTH the gauntlet and the live gate, resolving the E8-vs-F contradiction F4), and a REAL deterministic CodeScent adapter is deferred to Track-B (filed in H7). The gauntlet's anti-vacuity value comes from the 4 real-producer stages (`policy_compliance`, `contract_lock`, `run_check`, `test_execution`). *Confirm cut + advisory + Track-B-adapter — OR restore the hard catch if you want `code_quality_delta` discriminating in the gauntlet at M4 (then F5 ships the injected run, honestly labeled in DONE.md as a fixture-oracle stand-in, not a real quality gate).*

18. **C3/C4 integrity probes BUILT but live-admission DEFERRED (C3 `required_artifacts`, C4 `falsifier_preservation`/`falsifier_survival`) — does NOT contradict a ratified decision (Decision 4 named only provenance/canary as required producers), but surfaced here at the same altitude as 13/16/17 for visibility.** **Default shipped (recommended): admit only the NON-decorative integrity probes to live `required_probes` — `mount_boundary` (C1) and `mapping` (C2, real oracle triple).** `required_artifacts` and `falsifier_*` are still BUILT and proven to discriminate, but via the existing static `SentinelTournament` trip cases + producer-driven unit tests — NOT admitted to the live loop's `required_probes`, because the known-good reference supplies an empty required-artifact set and no falsifier seeds, so a live admission would be **decorative** (the probe can never fail for the reference; its "live fail-closed" claim would be vacuous). The `SentinelTournament` trip cases are the anti-vacuity backstop (already green pre-M4). *Confirm BUILD-but-defer-live-admission — OR restore live admission if you want a real required-artifact set + falsifier seeds wired into the reference's contract at M4 (then C3/C4 add the reference producers first, and live admission follows the same atomic-with-un-laundering discipline as C1/C2).*

19. **`replay_divergence` store-persistence + hard-gate-vs-not-assessable (B1) — surfaced in adversarial review; does NOT contradict a ratified decision, but it undercuts the "0.925 / no re-tune" headline (§9) and is the subtlest vacuity in M4.** B1 maps a *first observation* (no persisted baseline) to `:none` (the measured-GOOD token, 1.0), not to the not-assessable middle (`:unknown`/0.5). Because the `BaselineStore` is per-checkout and empty on every fresh CI clone, EVERY CI run is a first observation → replay is **structurally always `:none` in CI** and can fire `:diverged` ONLY via a hand-injected store (B1 test-3 / the m1_codex tampered third run) — never via the real per-checkout store, violating A7's "BROKEN case must go through the real producer." Worse, first-observation → `:none` (1.0) is itself the laundering A1 forbids for other signals (a first observation genuinely *cannot* assess reproducibility), and it is **load-bearing**: honest not-assessable (0.5) makes cold-start `0.85 < 0.9` → reference parks → real re-tune forced. **Default shipped (recommended): make this an explicit decision, not a silent laundering.** Two coherent options — **(a)** demote replay to *not-assessable-without-a-baseline* (excluded from `trustworthy?`, scored 0.5/boost when no baseline exists; a HARD `:none`-required gate only once a baseline exists), and own the implied cold-start re-tune (lower `auto_accept` to ~0.85 or reweight, recorded against the reference + re-verified against the gauntlet so no mutant auto-accepts); or **(b)** keep first-observation → `:none` but (i) add the `replay earned?` honesty flag to the §9 anchor table, (ii) drop the unconditional "no re-tune needed" phrasing, and (iii) decide where the baseline persists so the signal can ever discriminate (commit a per-plan baseline, key a CI cache on `contract_sha256`, or accept replay only discriminates in the live cross-run path on a durable box). EITHER WAY: add a discrimination test that fires `:diverged` through the REAL producer + REAL store (two runs whose scaffolding genuinely differs, e.g. a base test flaky-red on run 2); if no realistic input can do so, that is the proof replay is too narrow to be a hard gate and should be demoted per (a). And reframe B1's claim — it detects non-deterministic verification *scaffolding* across runs of the same base, NOT a divergent/"mutated" agent implementation. *Decide (a) demote-to-not-assessable-with-re-tune vs (b) keep-laundered-but-flag-and-persist; and confirm the store-persistence model.*

---

## 14. Appendices

### Appendix A — file:line index

The load-bearing files and the slices that touch them. (Line numbers are as verified by the designers at plan time; confirm before editing.)

| File | Key lines | Touched by |
|---|---|---|
| `lib/conveyor/gate/trust_evidence.ex` | `:25-33` from_run_output; `:47-62` the laundering (`:49` cal, `:52` base, `:54-56` integrity, `:58-59` replay, `:61-62` corpus) | A1 (calibration + baseline), B1 (replay + corpus), D4 (integrity clause) |
| `lib/conveyor/gate/trust_score.ex` | `:58-65` weights; `:65` threshold; `:89` band; `:105-110` trustworthy?; `:114-132` component scores | A6/H3 (anchor; no number change) |
| `lib/conveyor/gate/finalizer.ex` | `:28-42` abstain branch (critical-override clause hoisted FIRST here); `:97-106` persist_gate_result; `:161-168` policy_blocked; `:181-197` critical/policy categories | A3/A5 (abstain), E0 (verdict), E5/E9 (reachability), **E7 (critical-finding precedence above `passed?`; scoped to `canary_false_negative`/`severity:critical`, excludes `stale_canary`)** |
| `lib/conveyor/stations/baseline_health.ex` | `:11-22` no-runner stub | A2 |
| `lib/conveyor/baseline_health.ex` | `:19-33` empty-suite → :passed | A2 |
| `lib/conveyor/stations/acceptance_calibration.ex` | `:11-25` no-runner fabrication | A4 |
| `lib/conveyor/acceptance_calibration.ex` | `:25-47` calibration_attrs clauses | A4 |
| `lib/conveyor/eval/toolchain_runner.ex` | `:88-93` verification_result; `:103-108` digest-before-integrity ordering; `:116-130` hermeticity/docker_available?; `:228-250` integrity_observations + hermeticity_observation; `:332-336` suite/3 empty-suite leak | A7d, B (digest), C (probes), D (docker), F |
| `lib/conveyor/evidence/verification_rerunner.ex` | `:32-37, :212-218` production empty-suite leak | A7d |
| `lib/conveyor/gate/stages/test_execution.ex` | `:48` rerunner; `:111-179` findings/require_suite/calibration | A7d, E |
| `lib/conveyor/planning/serial_driver.ex` | `:31-36` 4-stage list; `:135-163` replay_report/normalize_replay_event; `:198-229` run_one_single_attempt/rework; `:367-404` run_gate!/default_gate_context; `:492, :505-508` trust_evidence; `:380` gate_code_sha256 | B1/B3, E0–E7, D (consumer) |
| `lib/conveyor/replay/*` (new) | slice_divergence.ex, baseline_store{,/file}.ex, event_normalizer.ex, corpus_pass_rate.ex | B1, B2 |
| `lib/conveyor/verification/integrity_sentinel.ex` | `:23-30` hermetic_controls; `:70-200` the 10 probes | C (reads, does not edit @default_probes) |
| `lib/conveyor/verification/integrity_probes.ex` (new) | mapping/required_artifacts/falsifier_* | C1–C4 |
| `lib/conveyor/stations/verify.ex` | `:10` @integrity_probes; `:27-30` IntegrityEvidence.verdict; `:44-51` runner_opts (backend threading); `:45` venv_opts | C1 (backend-dependent required_probes), D3/D5 |
| `lib/conveyor/gate/integrity_evidence.ex` | `:39-56` verdict wrapper | C (reads) |
| `lib/conveyor/planning/run_spec_assembler.ex` | `:109-130` station-input asymmetry (verify branch `:125-130`) | A2/A4 (inject workspace), D3 (backend) |
| `lib/conveyor/gate/hermetic_backend.ex` (new) | decide/1, station_input/1 | D2 |
| `lib/conveyor/gate/pipeline.ex` (new) | @full 14-stage table, code_sha256/0, midflight/full/required_keys | E0, E7 |
| `lib/conveyor/factory/gate_result.ex` | `:30-42` schema (add verdict) | E0 |
| `lib/conveyor/gate/midflight_check.ex` | `:31-36` own stage list + allowlist | E0 |
| `lib/conveyor/attempt_loop.ex` | `:238` gate_stages default; `:266-268` trust_evidence | E0, D (consumer) |
| `lib/conveyor/gate/stages/*.ex` | all 14 stage modules (workspace_integrity, observed_risk, policy_compliance, run_check, acceptance_mapping, provenance_attestation, canary_freshness, build_install, code_quality_delta, reviewer_aggregation, …) | E1–E8 |
| `lib/conveyor/gate/gate_provenance_context.ex` (new) | from/4 (surfaces existing digests) | E6 |
| `lib/conveyor/jobs/run_gate_canary.ex` | freshness key + GateHealth upsert; `:56-73` vacuous patch_set | E7 (producer), F (do-not-extend) |
| `lib/conveyor/eval/mutant_gauntlet.ex` | `:27` manifest path; `:29` @stages [TestExecution]; `:49-66` split/deferred; `:75-89` metrics/emit | F1–F7, H2 |
| `lib/conveyor/eval/mutant_context.ex` (new) | assemble/changed_files/contract_bundle/artifact_content/code_quality_run | F1–F5 |
| `lib/conveyor/eval/corpus_gauntlet.ex` (new) | per-sample emit, no @suite collision | H2 |
| `lib/conveyor/eval/falsifier_probe.ex` (new) | targets/run/metrics/emit | H5 |
| `lib/conveyor/genome/back_edge.ex` | `:42, :44, :60-72` edge_sha256 over full attrs incl. nonces | G1 |
| `lib/conveyor/factory/code_provenance_edge.ex` | `:77-79` unique_edge_sha256 identity | G1 (upsert target; unchanged) |
| `priv/repo/migrations/20260620110000_*.exs` | the unsafe up/down (DO NOT edit) | G2 (new forward migration only) |
| `priv/repo/migrations/20260622120000_dedupe_safe_*.exs` (new) | dedup-safe up + down | G2 |
| `samples/*/.conveyor/canary/mutants.json` | tasks_service 8 mutants; beads 7 behavioral; gx none | E10, F2–F8, H2 |
| `.github/workflows/ci.yml` | rung0 → replay → lift → scorecard --gate chain | D7, H2, H7 |

### Appendix B — discrimination-test catalogue

Every test the plan adds (or inverts), one line each. The GOOD half (reference → accept) and BROKEN half (defect → park/reject with the exact category) live in the same file per signal.

**Foundations (A):**
- `test/support/trust_discrimination.ex` (new helper) — `assert_discriminates/1`, `band_of_output/1`; the anti-vacuity contract for all of M4.
- `test/conveyor/gate/reference_auto_accept_test.exs` (new) — the reference auto-accepts at score 0.925 at every M4 stage (loop_integrity anchor).
- `test/conveyor/gate/trust_evidence_test.exs` (rewrite `:45-48`, `:50-59`) — absent calibration/baseline → abstain; measured-good → auto_accept; `from_run_output(%{})` emits `:not_assessed`/`:unknown` (no laundering); declared-N/A non-blocking.

**Baseline (A2/A3):**
- `test/conveyor/baseline_health_discrimination_test.exs` (new) — red baseline → `:failed` → abstain; no suite → `:not_assessed` → `:unknown` → abstain; green suite → auto_accept; `refute status == :passed` regression guard.
- `test/conveyor/gate/baseline_abstain_finalizer_test.exs` (new) — red baseline → `:abstained` + `:parked`; green → `:accepted`.

**Calibration (A4/A5) + empty-suite (A7d):**
- `test/conveyor/acceptance_calibration_discrimination_test.exs` (new) — tests-pass-on-base → `:invalid` → abstain; no locked tests → `:not_assessed` → abstain; genuinely-red-on-base → `:valid` → auto_accept; station does NOT fabricate `:valid` without running.
- `test/conveyor/gate/calibration_abstain_finalizer_test.exs` (new) — `:invalid` → `:abstained` + `:parked`; `:valid` → `:accepted`.
- `test/conveyor/gate/empty_acceptance_suite_test.exs` (new) — zero-test acceptance_locked suite → gate `:failed` (`empty_acceptance_suite`); absent suite → `missing_acceptance_locked`; ≥1 passing test → `:passed`; `VerificationRerunner` no-acceptance-suite → `:failed` (refute `:passed`).

**Replay/corpus (B):**
- `test/conveyor/replay/slice_divergence_test.exs` (new) — first observation → `:none` (records baseline); clean replay → `:none`; **mutated baseline → `:diverged`** (the falsifier); unfingerprintable → `:unknown`; corrupt baseline file does NOT silently pass.
- `test/conveyor/gate/trust_evidence_test.exs` (extend) — diverged → abstain; unknown → abstain; unrecognized shape → abstain (pins the laundering boundary); absent → auto_accept.
- `test/conveyor/m1_codex_production_loop_test.exs` (extend, `:eval`) — tampered-third-run: one slice `:parked` end-to-end while siblings pass.
- `test/conveyor/replay/corpus_pass_rate_test.exs` (new) — reads recorded fidelity; cold-start → `nil`.
- `test/conveyor/gate/trust_score_test.exs` (extend) — low corpus lowers score → abstain via threshold (not hard gate); cold-start `nil` corpus never blocks.
- `test/conveyor/planning/serial_driver_replay_report_test.exs` (new) — diverged slice → report `"diverged"` (BROKEN proof at report level).

**Pipeline (E0) + MutantContext (F1):**
- `test/conveyor/gate/pipeline_test.exs` (new) — single source for SerialDriver/MidflightCheck/AttemptLoop; midflight raises on TestExecution; E0 behaviorally == legacy 4-live (no false-park).
- `test/conveyor/gate/finalizer_test.exs` (extend) — verdict column written (`:accepted`/`:needs_rework`).
- `test/conveyor/eval/mutant_context_test.exs` (new) — changed_files parsed workspace-relative from each static patch (no `samples/` prefix); known_good from manifest.

**Static stages (E1–E5) + gauntlet (F2–F4; F5 cut):**
- `test/conveyor/gate/stages/workspace_integrity_discrimination_test.exs` (new) — reference passes; base-commit drift → `base_commit_mismatch`; missing head-tree → `missing_head_tree_sha256`; locked-path touch → `locked_path_touched` (routes to `:policy_blocked`).
- `test/conveyor/gate/stages/acceptance_mapping_discrimination_test.exs` (new) — 16 criteria pass; failed evidence → `failed_acceptance_evidence`; missing → `missing_acceptance_evidence`; empty criteria → `missing_acceptance_mapping`.
- `test/conveyor/gate/stages/run_check_discrimination_test.exs` (new) — reference bundle passes; tampered content → `artifact_hash_mismatch`; missing dossier → `missing_required_artifact`; injection marker → `untrusted_instruction_followed`.
- `test/conveyor/gate/stages/observed_risk_discrimination_test.exs` (new) — low-risk passes (+ RiskAssessment persisted); dependency change under `:fail_closed` → `observed_risk_exceeds_planned`; human-approval-required → `human_approval_required`; same under `:allow_with_warning` → warning, passes.
- `test/conveyor/gate/stages/policy_compliance_discrimination_test.exs` (new) — reference passes; protected policy edit → `policy_file_change`; blocked invocation → `policy_invocation_blocked`; Finalizer → `:policy_blocked` reachable.
- `test/conveyor/eval/mutant_gauntlet_static_test.exs` (new, `:eval`) — per HARD-catch static mutant (policy_compliance, contract_lock, run_check; NOT code_quality_delta — F5 cut): BROKEN (caught by expected stage+category), GOOD (known_good passes), DECOUPLING (remove the discriminating input → mutant passes, proving the catch is signal-driven).

**Integrity probes (C0–C5):**
- `test/conveyor/gate/integrity_source_mutation_gate_test.exs` (C0) — mutated source → abstain; clean → accept; flip-one-field anti-vacuity.
- `test/conveyor/gate/integrity_mount_boundary_gate_test.exs` (C1) — locked-path write → abstain (`mount_write_boundary_violation`); clean → accept.
- `test/conveyor/gate/integrity_mapping_gate_test.exs` (C2) — AC with no oracle → abstain (`obligation_mapping_missing`); empty refs → failed; fully-mapped → accept.
- `test/conveyor/gate/integrity_required_artifacts_gate_test.exs` (C3, UNIT-level — producer built, NOT admitted live in M4) — missing artifact → `untrustworthy` (`required_artifact_missing`) at the producer/sentinel level; present → passed. (Live admission deferred; static E8 trip case is the backstop.)
- `test/conveyor/gate/integrity_falsifier_gate_test.exs` (C4, UNIT-level — producer built, NOT admitted live in M4) — dropped seed → `untrustworthy` (`falsifier_dropped`); not-survived → (`falsifier_did_not_survive`); preserved+survived → passed. (Live admission deferred; static E8 trip cases are the backstop.)
- `test/conveyor/gate/integrity_reference_autoaccept_test.exs` (C1, `:eval`) — reference → `trustworthy` → auto_accept (the anti-regression spine).

**Hermetic gate (D):**
- `test/conveyor/eval/toolchain_runner_docker_available_test.exs` (D1) — daemon down → false; up → true; real daemon (`:eval`).
- `test/conveyor/gate/hermetic_backend_test.exs` (D2) — require_hermetic + docker absent → `{:unavailable, _}` (NOT `{:local,_}`); present → `{:docker, _}` with network=none; opt-out → `{:local,_}`.
- `test/conveyor/planning_run_spec_assembler_test.exs` (extend, D3) — hermetic_gate + docker absent → abstain key, no docker backend; present → backend=docker; off → unchanged.
- `test/conveyor/gate/trust_evidence_test.exs` (D4 invert `:12-17`, `:45-47`, `:50-59`) — `not_assessed` integrity → abstain; explicit `trustworthy` → auto_accept; the 3 vacuity-encoding tests inverted.
- `test/conveyor/stations/verify_test.exs` (D5, `:eval`) — venv resolves from the slice workspace, not tasks_service (assert tasks_service node-ids do NOT appear).
- `test/conveyor/eval/integrity_discrimination_live_path_test.exs` (D6, `:eval`) — through the REAL assembler/stations: docker-hermetic → accepted; network-open → abstained+parked; docker-absent → abstained+parked (no false-pass); src-rewrite → abstain; local-vs-docker `result_digest` equality.
- `test/mix/tasks/conveyor_eval_scorecard_hermetic_test.exs` (D7) — planted `hermetic_false_pass_rate: 0.5` → `--gate` exits non-zero; 0.0 → exits zero.

**Provenance/canary/advisory + reachability (E6–E10):**
- `test/conveyor/gate/stages/provenance_attestation_discrimination_test.exs` (E6) — docker full digests pass (+ persisted in-toto artifact); local missing container-image → non-blocking `provenance_container_not_assessed`; drop subject/invocation digest → exact missing-category; docker drops container-image → `missing_material_digest`.
- `test/conveyor/gate/stages/canary_freshness_discrimination_test.exs` (E7) — fresh green row → pass; no row → `stale_canary`; `false_negative_count > 0` → `canary_false_negative` + critical `:rejected` + stop_the_line incident; stale/key-mismatch → `stale_canary`.
- `test/conveyor/gate/stages/advisory_stages_test.exs` (E8) — build_install not_assessed (non-blocking); blocking finding RECORDED but non-fatal at M4; code_quality warning (would-block with a contract); reviewer not_required.
- `test/conveyor/gate/finalizer_reachability_test.exs` (E9) — policy edit → `:policy_blocked`; stale/false-negative canary → `:rejected` + incident; reference → `:accepted` (no false-park).
- `test/conveyor/eval/gate_corpus_discrimination_test.exs` (E10, `:eval`) — known-good passes both samples (zero false-positive); every enabled mutant caught by expected stage+category; meta-assertion that the static stages actually ran.

**Mutant gauntlet metric + falsifier (F6/F7):**
- `test/conveyor/eval/mutant_gauntlet_test.exs` (rewrite) — full ENABLED non-advisory corpus caught by expected stage (count DERIVED from the manifest, 7 today), `false_pass_rate == 0.0`, `deferred_static_stage` empty, `known_good` excluded; wrong-reason rejection counts as a false PASS.
- (F5 CUT) — no `code_quality_delta` hard-catch test; `code_quality_delta` advisory behavior covered by E8's `advisory_stages_test.exs`.
- F7 — `:local` hermeticity is `not_assessed` and never false-passes; `external_buggy_commit` (enabled) is caught.

**Data integrity (G):**
- `test/conveyor/back_edge_dedup_test.exs` (G1) — one mint → one edge; re-mint on a second gate_result → NO duplicate (same digest); different patch → distinct edge (dedup not over-broad). Proven red against unpatched code first.
- `test/conveyor/factory/artifact_projection_dedupe_test.exs` (G2) — distinct rows untouched; duplicate `(attempt, path)` → collapses to the single NEWEST row (Option A: scratch-table dedup SQL).

**Exit/validation (H):**
- `test/mix/tasks/conveyor_eval_scorecard_full_corpus_test.exs` (H2, `:eval`) — clean corpus → healthy → exit 0; planted false-pass → blocked → exit 6; negative-control flips it back.
- `test/conveyor/gate/trust_score_calibration_test.exs` (H3, default suite) — reference auto-accepts at shipped weights; one degraded signal → abstain; `policy_digest` pin.
- `test/conveyor/m4_abstain_end_to_end_test.exs` (H4, `:eval`) — real RED baseline producer output → Finalizer → persisted `:abstained` + `:parked` + no provenance/trust-bundle; all-good → `:accepted` + edges minted.
- `test/conveyor/eval/falsifier_probe_test.exs` (H5, `:eval`) — every one of the 4 FIXED `falsifier/` targets (DISTINCT from the F gauntlet corpus, so the check is independent not circular) caught/abstained for its NAMED reason (zero false-accepts, catch_rate 1.0); benign control auto-accepts (the critical anti-vacuity).
- `test/mix/tasks/conveyor_eval_live_report_test.exs` (H6) — first-pass/parked/cost computed from seeded fixtures; empty window → honest zeros, not fake-green.
- `test/conveyor/m4_done_checklist_test.exs` (H7) — every Part-A line has a backing test/command; unbacked line → fails.

---

*End of M4 Implementation Plan. Execute top to bottom per Section 7. Stay green at every commit. Do not commit or push unless Robert asks.*
