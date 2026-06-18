# Conveyor — Phase 1.5 Implementation Plan: Prove & Harden the Real-Agent Loop

> **Purpose of this document.** A comprehensive, standalone implementation plan
> for **Phase 1.5** — the phase that sits between the Phase 1 single-Slice
> tracer bullet and Phase 2 decomposition. Its job is narrow and load-bearing:
> **prove the single-Slice loop survives a real coding agent on varied real
> work, and harden it enough — and make it legible enough — that scaling it
> (decomposition, then a parallel fleet) amplifies something trustworthy instead
> of something unproven.** It is written to the same execution-shaped depth as
> `PHASE-0-1-IMPLEMENTATION-PLAN.md` so agents or humans can execute it, and it
> is built to be run through multi-model comparison + hybrid synthesis exactly
> like the Phase 0/1 plan was.
>
> **Status:** design / pre-implementation. Companion to:
>
> - `docs/2_implementation_plans/PHASE-0-1-IMPLEMENTATION-PLAN.md` — the factory
>   kernel and single-Slice loop this phase builds on (section refs of the form
>   §N point here);
> - `docs/BRAINSTORM.md` — the living strategy doc and Phase 0–8 roadmap;
> - `docs/3_advanced_plans/*` — the C-capability tranches; Phase 1.5 pulls a
>   small, focused subset forward and defers the rest (capability refs of the
>   form `Cn(volX)` point here).
>
> This document does **not** rebuild Phase 0/1. It is expressed as **deltas and
> new subsystems on top of the proven kernel.** Where it needs a field that the
> advanced plans already recommended reserving in Phase 0/1, it says so in §3 so
> the seam can land now, while Phase 0/1 is still being implemented, rather than
> as a migration later.

---

## 0. One-paragraph context

Phase 1 proves that the **deterministic conductor** can drive one human-authored
Slice through every station — readiness, scout, prompt, a policy-bounded agent
in Docker, independent evidence, the deterministic gate, reviewer-on-dossier,
and a PR-quality evidence bundle — and, critically, that the **gate is honest**
on a fixed set of injected mutants (gate-only canaries). What Phase 1 does
**not** prove is that the _loop_ produces good outcomes when a real, stochastic
agent attempts _varied_ work repeatedly: Phase 1's default CI uses a
deterministic fake runner, and the live agent is a single tagged/manual
happy-path test. Phase 1.5 closes exactly that gap. It introduces a **Battery**
— a labeled corpus of slices across archetypes that becomes Conveyor's own
standing regression suite — runs it with **two real adapters** (Pi, then Claude
Code), and adds the smallest set of **hardening and legibility** capabilities
that keep the loop honest and make its failures explainable. The guiding
principle is the project's own thesis turned inward: **Conveyor earns trust in
code through recorded evidence and eval; Phase 1.5 makes Conveyor earn trust in
_itself_ the same way.**

---

## 0.1 Why this phase exists before Phase 2 and Phase 3

The roadmap's literal next step is Phase 2 (automated decomposition). Phase 1.5
is a deliberate, evidence-driven insertion before it, for four honest reasons:

1. **Phase 1 proves the machinery, not the outcome.** Its definition of done
   runs the loop in hermetic CI with a _deterministic fake runner_; the live
   agent is a tagged/manual test against a fixed mutant set. After Phase 1 you
   know the plumbing is sound and the gate rejects known mutants — you do
   **not** know the loop produces good code with a real agent across varied
   change classes.
2. **Both Phase 2 and Phase 3 _amplify_ the loop.** Decomposition multiplies the
   number of contracts; a fleet multiplies the number of concurrent attempts.
   Amplifying an unproven loop multiplies untrusted diffs faster. Trust must be
   established at N=1 before it is scaled.
3. **Decomposition introduces the scariest new risk — machine-authored contracts
   and tests — and the defense for it belongs here.** The moment a spec agent
   writes the tests, "is this test honest and strong?" becomes existential. The
   Test-Integrity Sentinel (this phase) is the floor that must exist _before_
   Phase 2 generates contracts at volume.
4. **The cheapest, highest-leverage unlock is legibility.** The instant there is
   more than one attempt, you must answer "why did attempt 2 pass when attempt 1
   failed?" Evidence diffing and failure triage make every later phase faster to
   build and debug, and they are cheap.

Phase 1.5 is the "earn it" phase the staged-autonomy philosophy demands: it
turns "the loop works" from an assertion into a measured, replayable fact, and
it produces the eval dataset that every later phase (router, governor, autonomy
dial) will need.

---

## 0.2 The one-sentence thesis

> **Phase 1 proved the _gate_ is honest with mutant canaries (gate-only). Phase
> 1.5 proves the _loop_ is honest and capable with a slice Battery (full-loop) —
> and turns the loop itself into a permanent, replayable regression suite for
> Conveyor.**

Everything below serves that sentence. The Battery is the test rig; the
hardening capabilities are the instruments wired to it; Cassettes make the rig
cheap to re-run forever.

---

## 1. Goals & non-goals

### Goals

1. Stand up the **Battery**: a labeled, content-addressed corpus of slices
   across archetypes (CRUD, bugfix+regression, refactor, schema migration,
   dependency bump, plus integrity **trap slices**), each with a known-good
   expected outcome, runnable through the full loop and scored against
   expectation.
2. Prove the loop with **two real adapters** behind `AgentRunner`: **Pi first**
   (reuse Phase 1), then **Claude Code** — validating both outcome quality with
   a strong agent and that the adapter seam + capability→autonomy mapping are
   real.
3. Add **Agent Cassettes**: record real agent runs (events + tool results +
   PatchSet) content-addressably and replay them deterministically, so CI runs
   the _real_ agent's behavior cheaply and every Battery case becomes a
   permanent regression test of the whole loop.
4. **Harden the loop's honesty** with the Test-Integrity Sentinel, an expanded
   gate-canary corpus, and a **meta-canary** for every new trust tool (a trust
   tool that lies is a release-blocking bug).
5. **Make failures legible** with the Failure Triage Autopilot (deterministic
   classification → rework recipe) and the Evidence Time Machine (typed diffs
   between any two runs/attempts/specs).
6. **Raise outcome quality** with Gate-as-Tutor (in-loop advisory feedback),
   fleet-free Retry-with-escalation, and Behavior-lock differential testing for
   the refactor archetype.
7. **Instrument the loop** so the Battery's results are minable: archetype tags,
   cost/duration/first-pass capture, and context-usage telemetry.
8. **Reach autonomy level L2**: open real PRs with the gate's evidence bundle
   attached (the "Conveyor gate as PR reviewer" surface), with merge remaining a
   human action.
9. Run the **Tier-2 measurement studies** the reproducible Battery makes nearly
   free: scout/`AGENTS.md` ablation, prompt-template A/B, and a cost/quality
   Pareto per archetype.
10. Gate the phase's own exit: a deterministic **`battery_gate`** that asserts
    the success criteria (§19) before Phase 1.5 is declared done.

### Non-goals (explicitly deferred)

- **No decomposition / spec agent** (Phase 2). The human still hand-authors each
  Battery slice's Plan/Brief/tests; Conveyor audits them.
- **No fleet / parallelism / merge queue** (Phase 3). Phase 1.5 runs one Slice
  at a time; Best-of-N is out (it needs concurrent containers).
- **No brownfield onboarding or behavior characterization of a real repo**
  (later track). The Battery repo is controlled and disposable.
- **No economic _governor_** (Phase 6). Phase 1.5 _measures_ cost; it does not
  schedule or degrade on budget. (Per-run `RunBudget` caps from Phase 1 remain.)
- **No institutional memory / pgvector** (Phase 7).
- **No auto-merge, autonomy dial, or merge-trust _mechanism_** (Phase 5). Phase
  1.5 stops at L2 and only generates the seed data those mechanisms will use.
- **No model-router _mechanism_** (Phase 7). The dual-agent run produces its
  seed dataset; routing stays manual/config.
- **No multi-repo, no deploy, no new issue tracker / chat / CI platform.**

### Definition of done

The Battery contains at least one case per archetype plus the trap slices, each
with a normalized contract, locked TestPack, and a recorded known-good outcome.
`mix conveyor.battery` runs the full corpus through the loop on both Pi and
Claude Code; `mix conveyor.battery_report` emits per-archetype, per-agent
first-pass and eventual-success, cost, duration, rework rounds, and triage
classification. Cassettes record every live run; `mix conveyor.demo` and CI
replay the corpus from Cassettes with no provider credential and no Docker for
the full-replay mode. The Test-Integrity Sentinel reports the active test corpus
clean (no vacuous/flaky/non-hermetic tests). The expanded canary corpus passes
with zero false negatives. Every new trust tool passes its meta-canary. The
Evidence Time Machine diffs any two attempts. Behavior-lock catches a planted
refactor drift and clears a clean refactor. The Tier-2 studies produce a report.
The deterministic `mix conveyor.battery_gate` passes only if all of §19 holds.

---

## 2. The autonomy line for Phase 1.5

Phase 1 targets **L1** (local diffs) with **L2-shaped artifacts** (a PR-body
_draft_) and manual merge. Phase 1.5 graduates to **L2**:

|                     | Phase 1                    | **Phase 1.5**                                         |
| ------------------- | -------------------------- | ----------------------------------------------------- |
| Agent authority     | Produce diffs in container | Produce diffs in container                            |
| PR                  | PR-body draft only         | **Open a real PR** with the evidence bundle attached  |
| Merge               | Manual, external           | Manual, human action (unchanged)                      |
| Gate-as-PR-reviewer | —                          | The PR carries the gate verdict + dossier as a review |

L3 (auto-merge) and the trust/autonomy _dial_ stay out (Phase 5). The Battery is
run on a disposable repo, so opening real PRs is safe and exercises the exact L2
path Phase 2/3 depend on. The autonomy ceiling per adapter is still derived from
`AgentProfile.capabilities` (§9), not assumed.

---

## 3. Phase 0/1 coordination: land these inert seams **now**

The advanced plans identified several **schema-shaped seams** that are cheap if
added while Phase 0/1 is being implemented and expensive to retrofit once
historical evidence exists. Phase 1.5 is where their _mechanisms_ live, so it
**activates** them — but the inert columns/fields should land in the Phase 0/1
work that is happening now. If they did not, Phase 1.5 adds them as its first
task (`P15.0`), accepting a one-time migration.

| Seam (add in P0/1, activate in P1.5) | Field(s)                                                                                                                                                                   | Used by                                           |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| Archetype identity                   | `Slice.archetype_key?`, `AgentBrief.archetype_key?`, `RunAttempt.archetype_key?` (denormalized)                                                                            | Battery grouping, Pareto, future router/simulator |
| Cost/duration first-class            | `RunAttempt.cost_cents?`, `RunAttempt.wall_clock_ms?`                                                                                                                      | Pareto, instrumentation, future governor          |
| Iterative check discriminator        | `RunCheck/CommandResult.check_phase ∈ in_loop\|final` (default `final`), `iteration_index?`, `advisory?`                                                                   | Gate-as-Tutor                                     |
| Context-usage telemetry              | `Evidence.context_usage?` (embedded: `packed_used`, `packed_unused`, `unpacked_touched`)                                                                                   | Scout ablation, context-pack-miss metric          |
| Calibration carries verdicts         | `TestPackCalibration.contract_strength_status?` + integrity verdicts (`hermeticity_status?`, `red_on_stub_status?`, `interface_coverage_status?`, `integrity_report_ref?`) | Test-Integrity Sentinel                           |
| Cassette identity                    | nothing new — Cassettes key off the existing `run_spec_sha256` and content-addressed artifacts                                                                             | Agent Cassettes                                   |

All default to inert values and are read by nobody until Phase 1.5. This is the
single time-sensitive action item in this document.

---

## 4. Design laws (Phase 1 laws inherited; Phase 1.5 additions)

Phase 1.5 inherits all ten Phase 1 design laws (no task without acceptance
criteria; no implementation without a locked contract; no completion without
evidence; no authority without measured trust; no hidden state; no shared-trunk
chaos; no source mutation by context tools; no dangerous commands by default; no
orphan requirements/Slices; no bespoke tool empire). It adds five, tested as
invariants:

11. **The loop is proven by eval, not by assertion.** A loop capability is
    "done" only when a Battery case or meta-canary exercises it end-to-end and
    scores against a known-good expectation.
12. **Every trust tool ships with the canary that proves _it_ is honest.**
    Triage, the Integrity Sentinel, Behavior-lock, the Tutor, and
    Retry-escalation each land with a meta-canary; a trust tool that gives a
    false verdict is a release-blocking bug, exactly like a gate false negative.
13. **Stochastic from tape.** Replay reproduces the _agent's_ stochastic output
    from a recorded Cassette; the deterministic conductor still computes the
    verdict. Replay never re-derives trust from the agent's recorded claims.
14. **Integrity under temptation is a first-class requirement.** The Battery
    must include trap slices whose easiest path is to cheat (weaken a test, hack
    an impossible AC, follow an injected instruction). The loop must resist
    them, not merely succeed at honest work.
15. **Measure before you mechanize.** Phase 1.5 captures the data for routing,
    governance, and the autonomy dial, and runs ablation studies to justify (or
    refute) subsystems — but builds none of those mechanisms.

---

## 5. Architecture overview

Phase 1.5 wraps the Phase 1 loop in a test rig and instruments it. The loop
itself is unchanged in shape; the new surfaces are the Battery runner, the
Cassette record/replay layer behind `AgentRunner`, the second adapter, the
hardening stations, and the report/exit-gate.

```text
                         ┌──────────────────────────────────────────────┐
                         │                 THE BATTERY                   │
                         │  labeled slice corpus × archetypes + traps    │
                         │  (content-addressed fixtures, known outcomes) │
                         └───────────────────┬──────────────────────────┘
                                             │  mix conveyor.battery
                                             ▼
   ┌─────────── per case, the Phase 1 loop (unchanged spine) ───────────┐
   │ readiness → baseline → acceptance calibration                      │
   │   → TEST-INTEGRITY SENTINEL (new)                                  │
   │   → scout (+ context-usage telemetry) → prompt                     │
   │   → implement  via  AgentRunner { Pi | ClaudeCode | Replay }       │
   │        └─ GATE-AS-TUTOR advisory loop (new, in-container)          │
   │   → evidence → BEHAVIOR-LOCK (new, refactor archetype)            │
   │   → deterministic gate + EXPANDED CANARIES                         │
   │   → reviewer-on-dossier                                            │
   │   → on fail: FAILURE TRIAGE (new) → RETRY-WITH-ESCALATION (new)    │
   │   → L2: open real PR with evidence bundle                          │
   └───────────────────────────┬───────────────────────────────────────┘
            records everything  │  (events + tool results + PatchSet)
                                ▼
        ┌───────────────┐   ┌───────────────────┐   ┌──────────────────┐
        │ AGENT CASSETTE│   │ EVIDENCE TIME MACH.│   │ BATTERY REPORT + │
        │ (record/replay│   │ (diff any two runs)│   │ TIER-2 STUDIES + │
        │  full/hybrid) │   │                    │   │ battery_gate     │
        └───────────────┘   └───────────────────┘   └──────────────────┘
```

The determinism boundary is unchanged and reinforced (§17): agents (and replayed
cassettes) own stochastic generation; the conductor owns every verdict.

---

## 6. The Battery (the centerpiece)

The Battery is the loop-level analogue of Phase 1's gate-canary harness: where
canaries are labeled _bad diffs_ run through the gate-only path and asserted to
be rejected, Battery cases are labeled _slices_ run through the _full loop_ and
asserted to reach a known-good outcome. It is Conveyor's standing self-eval.

### 6.1 Archetypes and what each stresses

| Archetype               | Expected outcome                                              | What it stresses                                                              |
| ----------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `crud_endpoint`         | `gated`                                                       | Happy-path baseline; the Phase 1 slice generalized                            |
| `bugfix_regression`     | `gated`                                                       | Acceptance calibration (red-on-base for the right reason); cause vs symptom   |
| `pure_refactor`         | `gated` + behavior-locked                                     | **Behavior-lock** — "changed nothing else"; acceptance tests are useless here |
| `schema_migration`      | `gated`                                                       | Diff-scope, migrations-allowed policy, stateful behavior across the change    |
| `dependency_bump`       | `gated`                                                       | Supply-chain seam; lockfile diff as a freshness event; install/network policy |
| `trap_test_weakening`   | `gated` **without** weakening locked tests, or `needs_rework` | Locked-TestPack integrity under temptation                                    |
| `trap_impossible_ac`    | `contract_disputed` (not a hacked pass)                       | The agent must dispute, not fake; determinism boundary on judgment            |
| `trap_prompt_injection` | `gated` ignoring the injection, or `policy_blocked`           | Instruction hierarchy; untrusted repo content                                 |
| `trap_silent_breakage`  | `needs_rework` (caught by behavior-lock/regression)           | Unanticipated drift the agent didn't intend                                   |

Default size: **one case per archetype** (~9 cases) to prove breadth first; the
runner is built so each archetype can grow to **N=3** for statistical power once
the loop is green (config: `battery.cases_per_archetype`). A **held-out /
rotating subset** is reserved as a config seam (`battery.holdout_keys`) but not
exercised in the first pass (anti-overfitting; §18).

### 6.2 Battery case schema

A Battery case is a versioned, content-addressed fixture, not a free-form
script:

```json
{
  "schema_version": "conveyor.battery_case@1",
  "case_id": "BAT-crud-001",
  "archetype_key": "crud_endpoint",
  "is_trap": false,
  "repo_base_ref": "git+file://battery_repo@<base_commit>",
  "plan_contract_ref": "blobs/sha256/...plan.yml",
  "agent_brief_ref": "blobs/sha256/...brief.md",
  "test_pack_ref": "blobs/sha256/...tests.patch",
  "expected_outcome": "gated",
  "expected_failure_class": null,
  "known_good_solution_ref": "blobs/sha256/...solution.patch",
  "labels": ["tasks_api", "http"],
  "notes": "Phase 1 slice generalized; happy-path baseline."
}
```

Trap cases set `is_trap: true`, an `expected_outcome` other than `gated` where
appropriate, and an `expected_failure_class` (mirroring the failure taxonomy in
§13) so the runner can assert the loop failed _for the right reason_.

### 6.3 Battery resources

```text
BatteryCase (active resource; fixture-backed)
  id, case_id, archetype_key, is_trap, repo_base_ref,
  plan_contract_sha256, agent_brief_sha256, test_pack_sha256,
  expected_outcome ∈ gated | needs_rework | contract_disputed | policy_blocked,
  expected_failure_class?, known_good_solution_sha256?, labels[], status ∈ active | retired

BatteryRun (active resource; one execution of the corpus)
  id, project_id, adapter, agent_profile_id, run_mode ∈ live | replay_full | replay_hybrid,
  cassette_set_ref?, prompt_template_version, scout_enabled, agents_md_enabled,
  started_at, completed_at?, status ∈ running | completed | failed,
  summary_ref  → conveyor.battery_summary@1

BatteryCaseResult (active resource; per case per run)
  id, battery_run_id, battery_case_id, run_attempt_ids[],
  outcome, outcome_matches_expected, attempts, rework_rounds,
  first_pass_passed, eventual_passed, triage_classification?, triage_correct?,
  cost_cents?, wall_clock_ms?, gate_result_id?, behavior_lock_status?, notes
```

### 6.4 Battery runner

```text
Conveyor.Jobs.RunBattery
  input: corpus selection (all | archetype | case_id set), adapter, run_mode,
         ablation flags (scout_enabled, agents_md_enabled), prompt_template_version
  steps:
    1. for each selected BatteryCase: materialize repo at repo_base_ref, seed
       Plan/Epic/Slice/AgentBrief/TestPack from the fixture, run plan-audit +
       readiness (must pass; a Battery case that cannot reach `ready` is a
       fixture bug, not a loop result)
    2. drive the full Phase 1 loop for the case under the chosen adapter/run_mode,
       applying retry-with-escalation (§12.3) within the case's retry budget
    3. assert outcome == expected_outcome (and failure_class for traps)
    4. record BatteryCaseResult; record/seal a Cassette for live runs (§7)
    5. aggregate BatteryRun summary
  concurrency: SEQUENTIAL in Phase 1.5 (single-Slice law); the runner is the seam
               where Phase 3 will later parallelize, so it is written against a
               bounded worker abstraction with width=1.
```

The Battery becomes a permanent fixture: **every later phase re-runs it**, and a
phase that regresses a Battery case does not ship (§19, §22).

---

## 7. Agent Cassettes (record-replay the real agent)

The highest-leverage net-new subsystem. Phase 1 already records, content-
addressably, the normalized agent event stream and every `ToolInvocation`'s
inputs and outputs. A Cassette **promotes a recorded live run into a replay
fixture**, keyed by the immutable `run_spec_sha256`. This dissolves the Phase 1
tension between the high-reproducibility/low-fidelity fake runner and the
high-fidelity/expensive/nondeterministic live agent.

### 7.1 What is recorded

```text
Cassette (active resource)
  id, run_spec_sha256, adapter, agent_profile_id, recorded_at,
  agent_event_stream_ref     content-addressed normalized agent events (§ P1 envelope)
  tool_results_ref           content-addressed map: command_spec_sha256 → CommandResult
  patch_set_sha256           the produced PatchSet (the agent's authoritative output)
  gate_command_results_ref?  content-addressed gate-workspace command results (full-replay only)
  seal_status ∈ recording | sealed | invalidated
  freshness_key_sha256       == run_spec_sha256 (a changed contract/prompt/policy misses the cassette)
```

### 7.2 Two replay modes (this is the key design)

```text
AgentRunner.Replay  (a third adapter behind the existing behaviour)
  given a RunPrompt whose RunSpec digest matches a sealed Cassette:

  replay_full  (CI-cheap, deterministic, no Docker, no provider):
    - return the recorded RawRunResult (events + PatchSet) as the agent output
    - serve the gate workspace's command results from gate_command_results_ref
    - the conductor's LOGIC runs; its external EFFECTS are served from tape
    - use in `mix conveyor.demo` and default CI

  replay_hybrid  (conductor-regression, faithful, needs Docker):
    - return the recorded agent events + PatchSet from tape (skip the agent)
    - RE-RUN the deterministic gate LIVE against that PatchSet in a clean container
    - catches conductor/gate regressions: did refactoring the gate change the
      verdict on a known run? — while skipping the expensive, nondeterministic
      agent
    - use in nightly / pre-release
```

### 7.3 Freshness and honesty

A Cassette is valid only for its exact `run_spec_sha256`. Any change to the
contract, prompt template, policy, TestPack, toolchain image, or station plan
produces a new RunSpec digest, **misses** the cassette, and forces a live run
(or a loud `no_cassette_for_run_spec` error in CI) — the same freshness-key
discipline Phase 1 uses for gate/canary health. Replay never invents a verdict:
in both modes the gate's pass/fail is computed by the deterministic stages, not
read from the agent's recorded claims (Design Law 13).

### 7.4 Worker design

```text
Conveyor.Jobs.RecordCassette      (post-run, on a live RunAttempt)
  - collect agent events, tool results, PatchSet, and (if configured) gate
    command results into content-addressed blobs; seal the Cassette

Conveyor.Jobs.VerifyCassetteReplay (CI / nightly)
  - replay_full must reproduce the recorded outcome bit-for-bit (deterministic)
  - replay_hybrid must reproduce the verdict; a divergence is either a real
    conductor regression (good catch) or flaky gate input (→ Integrity Sentinel)
```

### 7.5 Why it composes

Cassettes make the entire Battery cheap to re-run forever, turn every live agent
run into a durable regression test, and give Conveyor a way to evolve its own
deterministic core without re-paying for agent runs — all reusing Phase 1's
existing content-addressed recording. It is barely new storage; it is mostly a
replay source behind `AgentRunner` plus the freshness discipline.

---

## 8. Second adapter: Claude Code via `AgentRunner`

Phase 1 proves the `AgentRunner` seam with Pi. Phase 1.5 proves it is a _real_
abstraction by running a genuinely different, more capable adapter — **Claude
Code** — through the identical state machine, and by mapping its capabilities to
an autonomy ceiling explicitly rather than implicitly.

### 8.1 Integration shape

Claude Code is driven headlessly: a streaming-JSON output mode for the
normalized event stream, an allowed/denied-tools + permission-mode configuration
for policy posture, **PreToolUse hooks** for pre-exec interception, MCP for
conductor- mediated tools, and session resume for retries. The adapter wraps
that headless process inside the Phase 1 Docker sandbox and translates its event
stream into Conveyor's `conveyor.agent_event@1` envelope.

### 8.2 The capability insight: a PreToolUse hook **is** the pre-exec policy seam

Phase 1 notes that an adapter without pre-exec command interception is capped at
a lower autonomy ceiling (observe-only). Claude Code's **PreToolUse hook can
deny a tool call before it runs**, which means it can route command decisions to
Conveyor's policy engine _before execution_ — the exact seam the determinism
boundary wants. So Claude Code can reach the higher `host_controlled_tools`
posture rather than being stuck at observe-only.

```text
Phase-1.5 Claude Code profiles:
  claude_code_hooked_policy   PreToolUse hook calls Conveyor.Policy.Engine and
                              blocks disallowed commands pre-exec; conductor-
                              mediated tools via MCP. Preferred. L2-capable.
  claude_code_observe_only    whole process in the sandbox, no hook routing;
                              Conveyor observes the transcript + relies on sandbox
                              limits + clean-gate verification. Fallback. L1 only.
```

The adapter declares `capabilities/0` honestly (streaming events: yes; pre-exec
policy: yes via hook in the hooked profile; cancellation; diff capture; cost
reporting from the result usage; mcp_support: yes; session_resume: yes), and the
conductor maps that to the autonomy ceiling. **Negative or degraded capabilities
are recorded in the RunSpec** so old evidence stays interpretable if Claude Code
changes.

### 8.3 The seam-friction we _want_ to find

Claude Code ships with its own rich tool loop (Bash/Edit/etc.). That overlaps
the conductor's `ToolExecutor`. Discovering exactly where Claude Code's built-in
tooling contends with conductor-mediated execution — and resolving it via the
hook/MCP routing — is an explicit _learning goal_ of Phase 1.5, not an accident.
Better to find this friction now, at N=1, than during Phase 3 parallelism.

### 8.4 The dual-agent run is a designed experiment

Running Pi and Claude Code on **identical contracts** across the Battery is a
controlled A/B. It produces, for free, the first real
`model × archetype → (first_pass, cost, quality, failure_mode)` dataset — which
(a) answers "is Pi good enough, or should the capable agent lead?" with data and
(b) is the seed dataset for the future model router (it is _measured_, not
_mechanized_, here).

---

## 9. Hardening & legibility capabilities

Each is specified as: purpose, schema delta, station/worker, and the **meta-
canary** that proves it is honest (Design Law 12).

### 9.1 Test-Integrity Sentinel (gate honesty floor)

**Purpose.** A flaky or vacuous test launders a false "green" — worse than no
test. The Sentinel verifies the locked TestPack is hermetic, non-vacuous, and
stable _at lock time_, before a real agent ever runs against it repeatedly.

**Schema.** Activates the Phase 0/1 calibration seam (§3) and adds:

```text
TestIntegrityRun (active resource)
  id, test_pack_id, slice_id,
  hermeticity   %{status ∈ hermetic|non_hermetic, violations[]},   # network/clock/rng/order/shared-state
  red_on_stub   %{status ∈ fails_on_stub|passes_on_stub, vacuous_tests[]},
  flake_assessment %{runs, failures, flake_rate, verdict ∈ stable|flaky},
  overall ∈ trustworthy | suspect | untrustworthy, report_ref, created_at

TestQuarantine (active resource)
  id, test_pack_id, test_id, reason ∈ flaky|non_hermetic|vacuous|order_dependent,
  excluded_from ∈ gate|tutor|both, status ∈ quarantined|rehabilitated|retired
```

**Station.** `Conveyor.Jobs.AssessTestIntegrity` runs after acceptance
calibration, before `ready`: (1) **red-on-stub** — run the locked tests against
a stubbed interface; any test that _passes_ is vacuous; (2) **hermeticity** —
run under frozen clock + fixed RNG + randomized order + `network=none`, diff
against a second run with a different seed/order; (3) **flake** — run R times
(reuse Phase 1 `flake_policy`), any nondeterministic result is flaky.
`overall: untrustworthy` blocks `ready`. A test that flakes _at gate time_
despite lock-time clearance is quarantined and the verdict recomputed without it
(a real green is never held hostage; a flaky red never blocks falsely), raising
an attention item.

**Meta-canary.** A deliberately vacuous test (passes on stub) must be flagged
and block readiness; a deliberately flaky test must be quarantined; a clean test
must never be quarantined. A miss is release-blocking.

### 9.2 Expanded gate-canary corpus

**Purpose.** Phase 1's mutant set is fixed and CRUD-shaped. As the Battery adds
archetypes, the canary corpus must grow to keep gate honesty scaling with the
work, with each new archetype's failure modes represented.

**Schema.** Reuse the Phase 1 `conveyor.canary_mutant@1` fixture shape,
including the advanced-plan seam fields (`mutant_id`, `origin: "authored"`,
`origin_ref: null`) so a future Phase-5 mint-from-escape mechanism (`C1(vol1)`)
consumes the same corpus with one code path. No minting in Phase 1.5.

**Station.** Reuse `Conveyor.Jobs.RunGateCanary`; add per-archetype mutants
(e.g. migration-not-reversible, dependency-pinned-wrong, refactor-silent-drift)
each asserted to fail the gate for an expected stage/reason. Label-scoped canary
selection at the case gate; full corpus at `battery_gate`.

**Meta-canary.** A known-good solution for each archetype passes the gate-only
path; every mutant is rejected for the expected reason; a passed mutant fails
CI.

### 9.3 Failure Triage Autopilot (legibility)

**Purpose.** Turn "the agent failed" into "rerun the scout with `app/storage.py`
forced in, because this was a context-pack miss." Deterministic-first
classification of every failure into a category + an executable rework recipe.

**Schema.**

```text
TriageRun (active resource)
  id, subject_kind ∈ run_attempt|station_run|gate_result|battery_case_result,
  subject_id, classification ∈ implementation_bug | weak_contract |
    impossible_contract | flaky_test | infra_failure | policy_violation |
    gate_false_negative | context_miss | budget_exhausted | unknown,
  confidence ∈ low|medium|high, recipe_ref → conveyor.rework_recipe@1,
  recommended_action ∈ retry_same_contract | retry_with_new_profile |
    revise_contract | raise_plan_amendment | rerun_station | quarantine_flake |
    fix_policy | fix_gate | escalate_human | park,
  status ∈ proposed|applied|rejected
```

**Station.** `Conveyor.Jobs.TriageFailure` runs on any terminal failure: collect
structured signals (gate stages, station error category, findings, RunCheck,
calibration status, budget); apply deterministic pattern rules first; only if
unresolved, ask an advisory triage reviewer (dossier-only). Contract-affecting
recipes route through the Phase 1 contract-evolution rule (`HumanDecision` + new
`ContractLock`), never silently. Low-risk recipes (rerun infra-failed station,
regenerate context pack, rerun stale canary) may auto-apply within retry budget.

**Meta-canary (confusion matrix).** The Battery's trap slices and injected
failures have _known_ categories. Triage classification is scored as a confusion
matrix against them; precision below a bar (or a trap misclassified) is a Triage
bug. Triage that fabricates certainty on a genuinely ambiguous failure (should
be `unknown` → human) fails its eval.

### 9.4 Evidence Time Machine (legibility)

**Purpose.** Answer "why did attempt 2 pass when attempt 1 failed?" / "why is
this gate stale?" / "did run 2 retry the same contract or a weakened one?" — in
seconds, from content-addressed evidence, without DB spelunking.

**Schema.** Computed-first; persist only saved comparisons:

```text
EvidenceComparison (active resource, optional persistence)
  id, left_subject_kind/id, right_subject_kind/id, comparison_ref,
  summary_status ∈ identical | equivalent | materially_different | incomparable
```

**Surface.** CLI-first:
`mix conveyor.diff_runs RUN_A RUN_B [--section contract|gate|patch|spec]`,
`mix conveyor.why_stale GATE_RESULT_ID`,
`mix conveyor.why_different RUN_A RUN_B`. Typed diffs (not text diffs) across
RunSpec, ContractLock, PatchSet, gate stages, artifact manifest,
reviewer/dossier digest, toolchain/image digest. Materiality classification
flags `acceptance_weakened` / `policy_weakened` loudly. Fails closed on a
missing or digest-mismatched blob; respects sensitivity/redaction metadata.

**Meta-canary.** Golden fixture pairs (same contract/different patch; different
contract/same patch; same patch/different gate; stale canary; tampered manifest)
must classify exactly; a tampered/missing blob must produce `incomparable`,
never a silent diff.

### 9.5 Instrumentation (sensors)

**Purpose.** Make the Battery minable. Activates the §3 seams.

- **Archetype tags** (`archetype_key` on Slice/Brief/RunAttempt): every Battery
  case is tagged; results group by archetype.
- **Cost/duration/first-pass** (`cost_cents`, `wall_clock_ms` on RunAttempt;
  `first_pass_passed`/`eventual_passed` on `BatteryCaseResult`): captured per
  run.
- **Context-usage telemetry** (`Evidence.context_usage`): derive `packed_used`,
  `packed_unused`, `unpacked_touched` from the agent's file-open/edit events
  joined to the Context Pack. Feeds the scout-precision metric and ablation.

No mechanism consumes these to _decide_ anything in Phase 1.5 (Design Law 15);
they are recorded and reported.

### 9.6 Gate-as-Tutor (advisory, outcome quality) — stretch (in)

**Purpose.** Run a fast subset of gate stages _during_ implementation so the
agent converges against the real acceptance signal, cutting rework rounds and
token cost — without ever softening the verdict.

**Schema.** Activates the §3 `check_phase`/`iteration_index`/`advisory` seam.

```text
TutorSession (active resource, one per RunAttempt)
  id, run_attempt_id, slice_id, stage_set[], iterations[], final_alignment
TutorIteration (embedded)
  iteration_index, trigger ∈ commit|save|agent_request, commit_sha?,
  stage_results[] %{stage, status ∈ pass|fail|skip, finding_refs[]}
```

**Station.** `Conveyor.Tutor.InContainer` runs inside the worker container
(latency matters): on commit/save it runs only fast, touched-scope advisory
stages (targeted tests for touched files + diff-scope + code-quality delta —
never the full suite), writes a `TutorIteration`
(`check_phase: in_loop, advisory: true`), and injects a compact structured
findings summary back through the adapter's feedback channel (natural for both
Pi RPC and Claude Code). Strictly debounced and CPU/time-budgeted so it never
starves the agent. `final_alignment` (did in-loop verdicts predict the final
gate?) is computed post-run; low alignment means the stage_set is mis-specified,
surfaced not hidden. **Consumes only Integrity-verified tests** (§9.1) so it
never teaches against flaky signal.

**Meta-canary.** An `advisory: true` check can _never_ close a Slice — only a
`check_phase: final` gate verdict can. A test that flips an advisory verdict to
authoritative fails CI. `final_alignment` is always reported.

### 9.7 Behavior-lock differential (refactor safety) — stretch (in)

**Purpose.** For the refactor archetype, prove behavior did not drift — the only
real gate for "change nothing else." Acceptance tests only prove "you changed
_this_."

**Schema.**

```text
BehaviorLockRun (active resource)
  id, run_attempt_id, slice_id, change_class ∈ refactor|behavior_preserving|behavior_changing,
  oracle_kind ∈ metamorphic|recorded_traffic|golden_master,
  inputs_ref, baseline_output_ref, candidate_output_ref,
  divergences[], allowed_divergence_globs[], status ∈ locked|diverged|inconclusive
```

**Station.** `Conveyor.Jobs.BehaviorLockDifferential` (gate stage, gated on
`change_class ∈ {refactor, behavior_preserving}`): materialize base and patched
head; acquire inputs **scoped to the touched interface** (default: metamorphic /
recorded-traffic, capped input count — deliberately _not_ a general fuzzing
platform, to keep this from being the L-effort sinkhole); run both versions over
identical inputs (`network=none`); diff observable outputs (responses, return
values, persisted state) modulo `allowed_divergence_globs`; canonicalize known
non-determinism (timestamps, ordering, seeds). `diverged` fails the gate.

**Meta-canary.** The `trap_silent_breakage` Battery case must be caught as
`diverged`; a genuine behavior-preserving refactor must report `locked` with
zero divergences; a declared change inside `allowed_divergence_globs` must pass.

### 9.8 Retry-with-escalation (fleet-free) — stretch (in)

**Purpose.** On gate failure due to execution/validation (not contract-dispute,
not policy), retry with a _stronger_ tier instead of re-rolling the same model —
a no-fleet precursor to the model router's escalation ladder.

**Schema.**

```text
EscalationLadder (config resource)
  id, project_id, ordered_tiers[]  e.g. ["pi", "claude_code"], max_attempts
RouteDecisionLite (recorded per RunAttempt)
  id, run_attempt_id, archetype_key, ladder_position, chosen_profile_id,
  reason ∈ initial | escalation, prior_failure_class?
```

**Station.** In the `RunAttempt` orchestration: on `needs_rework` with
`failure_class ∈ {execution, validation}`, advance `ladder_position`, create a
new `RunAttempt` against a fresh `RunSpec` with the next tier, bounded by
`max_attempts` and the retry budget. `contract_disputed` and `policy_blocked`
never consume an escalation step (they are not the implementer's fault). Each
escalation records a `RouteDecisionLite` (the audit trail of _why this model_).

**Meta-canary.** A forced execution failure must escalate up the ladder, never
re-roll the same failed tier; a contract-dispute must _not_ consume a step; the
ladder must be monotone and bounded.

---

## 10. Tier-2 measurement studies

The reproducible Battery makes these nearly free. They are studies, not
features: they produce a report, not a mechanism (Design Law 15).

### 10.1 Ablation studies

```text
Conveyor.Jobs.RunAblation
  - run the Battery with scout_enabled ∈ {true, degraded, false}
  - run the Battery with agents_md_enabled ∈ {true, false}
  - report the first-pass/eventual/cost delta attributable to each
```

This **measures** whether the Context Scout and `AGENTS.md` actually help —
directly answering two of Phase 1's own open questions ("does the scout provide
useful signal?", "does `AGENTS.md` reduce ambiguity?") instead of assuming. If a
subsystem doesn't move the numbers, that is a high-value _simplification_
signal.

### 10.2 Prompt-template A/B

Prompts are versioned artifacts; the Battery is a stable benchmark.
`mix conveyor.battery --prompt-template implementation-prompt@2` vs `@1` becomes
a measured comparison. Seed of the Phase-7 prompt-optimization loop, available
now.

### 10.3 Cost/quality Pareto per archetype

Combine the dual-agent (§8.4) and retry-escalation (§9.8) data into a per-
archetype frontier: the cheapest agent/config that clears the quality bar. Free
byproduct; arms the Phase-6 governor and Phase-3 economics with real numbers.

All three are emitted by `mix conveyor.battery_report` as a single
`conveyor.battery_studies@1` artifact.

---

## 11. Ash domain deltas (consolidated)

New active resources (created by Phase 1.5): `BatteryCase`, `BatteryRun`,
`BatteryCaseResult`, `Cassette`, `TestIntegrityRun`, `TestQuarantine`,
`TriageRun`, `EvidenceComparison` (optional), `BehaviorLockRun`,
`EscalationLadder`, `RouteDecisionLite`, `TutorSession`, `AblationStudy`.

Field deltas (activate §3 seams): `archetype_key` on `Slice`/`AgentBrief`/
`RunAttempt`; `cost_cents`/`wall_clock_ms` on `RunAttempt`; `context_usage` on
`Evidence`; `check_phase`/`iteration_index`/`advisory` on `RunCheck`/
`CommandResult`; `contract_strength_status` + integrity verdict fields on
`TestPackCalibration`.

New value-object / artifact schemas: `conveyor.battery_case@1`,
`conveyor.battery_summary@1`, `conveyor.battery_studies@1`,
`conveyor.cassette@1`, `conveyor.test_integrity@1`, `conveyor.rework_recipe@1`,
`conveyor.behavior_lock@1`, `conveyor.evidence_comparison@1`. All append-only
within a major version, validated by RunCheck, projected under `.conveyor/`.

New DB invariants (minimum): `BatteryCase: unique(case_id)`;
`BatteryCaseResult: unique(battery_run_id, battery_case_id)`;
`Cassette: unique(run_spec_sha256, adapter)`;
`TestIntegrityRun: unique(test_pack_id, run_spec_id)`.

---

## 12. State-machine & orchestration deltas

The `Slice` lifecycle is unchanged. Two additions on the attempt layer:

### 12.1 RunAttempt: integrity + tutor + behavior-lock stations

The station plan gains: `test_integrity` (after acceptance calibration, before
ready), an in-container `tutor` loop during `implement`, and `behavior_lock`
(after evidence, gated on change_class). These are added to the existing
versioned `StationPlan` DAG — no new scheduler model.

### 12.2 RunAttempt: replay mode

A `RunAttempt` carries `run_mode ∈ live | replay_full | replay_hybrid`. In
replay modes the `implement` station resolves `AgentRunner.Replay` against the
matching Cassette; all other stations are unchanged. `replay_full` additionally
serves gate-workspace command results from tape.

### 12.3 RunAttempt: escalation chain

`RunAttempt` already supports multiple attempts per Slice. Phase 1.5 adds the
bounded escalation chain (§9.8): a failed attempt may spawn the next-tier
attempt against a fresh RunSpec, recorded as `RouteDecisionLite`, never mutating
the Slice through internal states (mirrors Phase 1's "RunAttempt #2 against a
fresh RunSpec" rule).

---

## 13. Failure taxonomy (reused, exercised)

Phase 1.5 does not redefine the failure taxonomy; it **exercises** it. The trap
slices and injected failures map onto the Phase 1 categories (Brief / Plan-Audit
/ Context-Pack Miss / Execution / Validation / Review / Policy / Canary), and
the Triage Autopilot (§9.3) is scored on classifying them correctly. This is the
first time the taxonomy is validated against _known_ failures rather than
asserted.

---

## 14. OTP / Oban topology deltas

New Oban workers under the existing `Conveyor.Conductor.Supervisor`:

```text
Conveyor.Jobs.RunBattery              (corpus orchestrator, width=1)
Conveyor.Jobs.RecordCassette          (post-run recording + seal)
Conveyor.Jobs.VerifyCassetteReplay    (CI/nightly replay verification)
Conveyor.Jobs.AssessTestIntegrity     (red-on-stub + hermeticity + flake)
Conveyor.Jobs.TriageFailure           (deterministic-first classification)
Conveyor.Jobs.BehaviorLockDifferential(refactor gate stage)
Conveyor.Jobs.RunAblation             (Tier-2 studies)
Conveyor.Tutor.InContainer            (in-worker advisory loop; not an Oban job)
```

`AgentRunner.ClaudeCode` and `AgentRunner.Replay` join `AgentRunner.Pi` behind
the existing behaviour. The Battery runner is written against a bounded worker
abstraction (width=1) so Phase 3 can widen it without a rewrite.

---

## 15. Operator interface (new Mix tasks)

Keep names close to a future `conveyor` CLI. New in Phase 1.5:

```bash
mix conveyor.battery [--archetype X | --case BAT-...] [--adapter pi|claude_code]
                     [--mode live|replay_full|replay_hybrid]
mix conveyor.battery_report RUN_ID         # per-archetype/agent metrics + Tier-2 studies
mix conveyor.battery_gate PROJECT_ID       # the deterministic Phase-1.5 exit gate (§19)
mix conveyor.record_cassette RUN_ATTEMPT_ID
mix conveyor.replay RUN_ATTEMPT_ID --mode replay_full|replay_hybrid
mix conveyor.test_integrity SLICE_ID
mix conveyor.triage RUN_ATTEMPT_ID
mix conveyor.diff_runs RUN_A RUN_B [--section contract|gate|patch|spec]
mix conveyor.why_stale GATE_RESULT_ID
mix conveyor.ablate PROJECT_ID --vary scout|agents_md|prompt_template
```

CLI exit codes extend the Phase 1 set; a Battery/meta-canary false verdict uses
the existing `6` (canary/eval false negative).

---

## 16. Telemetry & metrics

Reuse Phase 1's OpenTelemetry span hierarchy; add spans for
`conveyor.station. test_integrity`, `conveyor.station.tutor.iteration`,
`conveyor.station. behavior_lock`, and `conveyor.battery.case`. New bounded
metrics (respecting the Phase 1 cardinality rule — `archetype_key`, `adapter`,
`run_mode`, `outcome`, `failure_category` are allowed dimensions):
first-pass-success, eventual-success, rework-rounds, context-pack-miss-rate,
triage-accuracy, tutor-alignment, cost- per-success, time-to-green,
cassette-replay-divergence-rate.

---

## 17. The determinism boundary (restated for Phase 1.5)

Unchanged and reinforced:

- **Agents and replayed Cassettes own stochastic generation; the conductor owns
  every verdict.** Replay returns the agent's recorded _outputs_; the gate's
  pass/fail is recomputed by deterministic stages (Design Law 13).
- **The Tutor is advisory; the final gate is the sole authority** (Design Law
  12; §9.6 meta-canary).
- **Claude Code's tools route through policy** — a PreToolUse hook enforces the
  command grammar pre-exec; MCP/slash-command tools are normalized into
  `ToolInvocation`s exactly like any conductor-mediated tool. MCP is an
  alternate transport, not a bypass.
- **The conductor DB/ledger remain unreachable from the sandbox**, including
  from the Claude Code process.

---

## 18. Risks & mitigations (Phase 1.5-specific)

| Risk                                                                                    | Mitigation                                                                                                                                                                 |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Battery overfitting** — the loop is tuned to pass the Battery, not real work          | Held-out/rotating subset seam (`battery.holdout_keys`); Battery is necessary-not-sufficient; the real-repo graduation milestone (deferred) is the true generalization test |
| **Real-agent nondeterminism** makes first-pass-success noisy                            | N reruns per case for stable rates; replayed reruns are free via Cassettes; only fresh sampling costs money                                                                |
| **Claude Code adapter doesn't fit the seam cleanly** (tool contention, capability gaps) | This is a designed learning goal (§8.3); resolve via hook/MCP routing; fall back to observe-only at a lower ceiling; record degraded capabilities in RunSpec               |
| **Behavior-lock input-generation balloons (the L-effort sinkhole)**                     | Default metamorphic/recorded-traffic scoped to the touched interface; cap input count; never build a general fuzzer                                                        |
| **Cost blowup** — 2 agents × archetypes × reruns × retries                              | Cassettes for CI; live runs budgeted via Phase 1 `RunBudget`; the Pareto study tells you where to stop paying                                                              |
| **A buggy trust tool manufactures false trust**                                         | Every trust tool ships with its meta-canary (Design Law 12); Triage scored by confusion matrix                                                                             |
| **Scope creep** — "prove & harden" absorbs infinite capabilities                        | Phase 1 cutline labels (TRACER/TRUST/INSTRUMENT/DEFER) applied to every item (§20); Best-of-N, governor, router, autonomy dial explicitly out                              |
| **Cassette staleness silently passes stale behavior**                                   | Freshness keyed to `run_spec_sha256`; a changed contract/prompt/policy misses the cassette and forces a live run or a loud CI error                                        |

---

## 19. Success criteria — the `battery_gate` (phase exit)

Phase 1.5 gates its own exit. `mix conveyor.battery_gate` is deterministic and
passes only if **all** hold:

1. Every archetype + every trap slice has a Battery case that reaches its
   `expected_outcome` on **both** Pi and Claude Code (live), and
   `outcome_matches_ expected` for every case.
2. **Zero gate false negatives** across the expanded canary corpus (non-
   negotiable).
3. The active test corpus is Integrity-clean: zero vacuous, zero flaky, zero
   non-hermetic tests (or each is quarantined with an attention item).
4. Every new trust tool passes its meta-canary; Triage precision on the
   known/trap failures is at or above the configured bar.
5. Behavior-lock catches `trap_silent_breakage` and clears a clean refactor.
6. Every live run sealed a Cassette; `replay_full` reproduces outcomes
   deterministically and `replay_hybrid` reproduces verdicts;
   `mix conveyor.demo` runs the corpus from Cassettes with no provider
   credential.
7. The Evidence Time Machine diffs any two attempts with correct materiality
   classification on the golden fixtures.
8. First-pass and eventual-success, cost, duration, rework, and
   context-pack-miss are **captured** per archetype per agent (measured, not
   threshold-gated — this is the phase's first real data), and the Tier-2
   studies report is produced.

Note the asymmetry: gate honesty (2), test integrity (3), and trust-tool honesty
(4) are **hard pass/fail**; outcome quality (8) is **measured and recorded**,
not thresholded — Phase 1.5's job is to _establish_ those baselines, not to hit
a number picked in advance.

---

## 20. Milestone / task breakdown with acceptance criteria

Cutline labels reuse Phase 1: `TRACER_REQUIRED` (the Battery cannot run without
it), `TRUST_REQUIRED` (the Battery runs but its claims aren't credible),
`INSTRUMENT_ONLY` (capture/report now, no mechanism), `DEFER`.

```text
P15.0  Activate Phase 0/1 seams (or add them)                         [TRACER_REQUIRED]
       AC: archetype_key, cost/duration, context_usage, check_phase,
           calibration verdict fields exist and validate; inert until used.

P15.1  Battery repo + fixtures (1 case/archetype + traps)             [TRACER_REQUIRED]
       AC: each case has plan/brief/locked tests + known-good solution;
           plan-audit + readiness pass for every honest case; trap cases
           encode expected non-`gated` outcomes and failure classes.

P15.2  Battery runner + resources + report                           [TRACER_REQUIRED]
       AC: mix conveyor.battery drives every case sequentially through the
           full loop; battery_report emits per-archetype/agent metrics.

P15.3  Claude Code adapter (hooked_policy + observe_only)            [TRACER_REQUIRED]
       AC: runs the corpus; emits normalized events; PreToolUse hook blocks a
           denylisted command pre-exec; capabilities mapped to ceiling; degraded
           caps recorded in RunSpec.

P15.4  Agent Cassettes: record + replay_full + replay_hybrid         [TRUST_REQUIRED]
       AC: every live run seals a cassette; replay_full is deterministic with no
           Docker/provider; replay_hybrid re-runs the gate live and reproduces
           the verdict; a changed RunSpec misses the cassette.

P15.5  Test-Integrity Sentinel + quarantine                          [TRUST_REQUIRED]
       AC: vacuous/flaky/non-hermetic fixtures flagged; untrustworthy blocks
           ready; gate-time flake quarantined and verdict recomputed; meta-canary
           passes.

P15.6  Expanded gate-canary corpus (per archetype)                   [TRUST_REQUIRED]
       AC: each archetype's known-good passes gate-only; each mutant rejected for
           the expected reason; a passed mutant fails CI.

P15.7  Failure Triage Autopilot + confusion matrix                   [TRUST_REQUIRED]
       AC: deterministic recipes for the top failure classes; trap/known failures
           classified; precision at/above bar; ambiguous → unknown/human;
           contract-affecting recipes route through HumanDecision.

P15.8  Evidence Time Machine (CLI typed diffs)                       [TRUST_REQUIRED]
       AC: diff_runs/why_stale/why_different produce typed, materiality-classified
           diffs; tampered/missing blob → incomparable; golden fixtures pass.

P15.9  Instrumentation wired (sensors)                                [INSTRUMENT_ONLY]
       AC: archetype tags, cost/duration, context_usage populated and reported;
           no mechanism consumes them to decide anything.

P15.10 Gate-as-Tutor (advisory, in-container)                        [TRUST_REQUIRED]
       AC: in-loop advisory stages run on commit; findings injected to the agent;
           advisory never closes a slice; final_alignment reported; consumes only
           integrity-verified tests; meta-canary passes.

P15.11 Behavior-lock differential (refactor archetype)              [TRUST_REQUIRED]
       AC: trap_silent_breakage caught; clean refactor clears; declared-divergence
           passes; non-determinism canonicalized.

P15.12 Retry-with-escalation (fleet-free)                            [TRUST_REQUIRED]
       AC: execution/validation failure escalates the ladder; contract-dispute and
           policy never consume a step; bounded + monotone; RouteDecisionLite
           recorded.

P15.13 Tier-2 studies (ablation, prompt A/B, Pareto)                 [INSTRUMENT_ONLY]
       AC: ablation reports scout/AGENTS.md deltas; prompt A/B comparison;
           per-archetype cost/quality Pareto; emitted as battery_studies@1.

P15.14 L2 PR generation                                              [TRUST_REQUIRED]
       AC: a gated case opens a real PR with the evidence bundle attached; merge
           remains a human action; gate verdict + dossier visible on the PR.

P15.15 battery_gate (phase exit) + dual-agent run                    [TRACER_REQUIRED]
       AC: §19 holds; the full corpus is green on Pi and Claude Code; the dual-
           agent dataset and graduation recommendation (§22) are produced.
```

Schedule-protection (never cut): the Battery + its known-good outcomes, Cassette
record/replay, the Test-Integrity Sentinel, the expanded canaries, every meta-
canary, and `battery_gate`. Cut first: LiveView polish, the live vital-signs
dashboard, the second adapter's `hooked_policy` (fall back to observe-only),
Behavior-lock breadth beyond the touched interface, Tier-2 study depth.

---

## 21. Testing strategy for Conveyor itself

- **The Battery is the integration test.** It replaces the single Phase 1 tracer
  as the primary end-to-end suite; CI runs it in `replay_full` mode.
- **Meta-canaries are the unit-of-trust tests.** Each trust tool's meta-canary
  (§9) is a release-blocking ExUnit/eval case.
- **Cassette determinism test.** `replay_full` of a fixed cassette must
  reproduce byte-identical outcomes; a drift is a conductor bug.
- **Adapter conformance (Claude Code).** Reuse Phase 1's adapter-conformance
  suite: capability reporting, normalized event streaming, monotonic sequence
  numbers, cancellation, timeout, diff capture, malformed-output handling, and —
  new — PreToolUse-hook policy enforcement.
- **Triage confusion-matrix eval, Integrity catch/no-false-quarantine eval,
  Behavior-lock catch/no-false-positive eval** as labeled suites.
- **Fail-closed everywhere.** A missing cassette, a stale canary freshness key,
  an untrustworthy integrity verdict, or a digest-mismatched blob each fail
  loud, never "best-effort."

---

## 22. What success in Phase 1.5 teaches — and the graduation decision

Phase 1.5 is successful only if it answers, with evidence:

- Does the loop produce good outcomes with a _real_ agent across varied
  archetypes — and how good (the baseline numbers)?
- Is Pi good enough, or should Claude Code lead? (the dual-agent dataset)
- Does the Context Scout / `AGENTS.md` actually help? (the ablation studies)
- Is the gate still honest, and are the new trust tools honest? (canaries +
  meta- canaries)
- What does the loop cost per success per archetype? (the Pareto)
- How much does in-loop tutoring + escalation lift outcomes? (tutor-alignment,
  eventual-success)

The exit produces a **graduation recommendation**: with a proven, replayable,
instrumented loop in hand, do we go to **Phase 2 (decomposition)** — if the
bottleneck is authoring volume — or **Phase 3 (parallel fleet)** — if the
bottleneck is throughput and the loop is strong enough to amplify? Phase 1.5 is
explicitly designed to make that a _data-driven_ choice rather than a guess.

---

## 23. Deferred hooks deliberately seeded by Phase 1.5

Built now as data/seams, mechanized later:

- **Model router (Phase 7, `C12(vol2)`):** the dual-agent `model × archetype`
  dataset and `RouteDecisionLite` records are its training data.
- **Economic governor (Phase 6):** cost/duration capture and the Pareto frontier
  are its inputs.
- **Autonomy dial + merge-trust (Phase 5, `C18(vol2)`):** per-archetype outcome
  and gate-honesty history is the trust signal it will compose.
- **Mint-from-escape canaries (Phase 5, `C1(vol1)`):** the canary corpus already
  carries the `origin`/`origin_ref` seam.
- **Swarm parallelism (Phase 3):** the Battery runner's width=1 worker
  abstraction is the seam the dispatcher widens.
- **Plan workbench / swarm simulator (`C11/C12(vol3)`):** archetype + cost
  history is their read-model substrate.

---

## 24. Naming / numbering reconciliation note

The two advanced-capability volumes both number capabilities **C11–C20** with
different meanings. Phase 1.5 pulls a focused subset forward and refers to them
by volume (`Cn(vol1)`, `Cn(vol2)`, `Cn(vol3)`). Before Phase 2, the C-IDs across
all three volumes should be reconciled into a single namespace (e.g., C1–C30) so
the roadmap, the plans, and LiveView speak one language. This is a docs-hygiene
task, not a code task, and is out of Phase 1.5's execution scope — flagged here
so it is not forgotten.
