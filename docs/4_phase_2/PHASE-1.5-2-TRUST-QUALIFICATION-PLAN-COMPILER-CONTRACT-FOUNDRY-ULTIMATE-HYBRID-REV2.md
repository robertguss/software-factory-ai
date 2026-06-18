# Conveyor — Phase 1.5 + Phase 2: Trust Qualification, Plan Compiler & Contract Foundry

> **Status:** ultimate hybrid brainstorming draft — **revision REV2** (round-2
> review folded in); not yet committed for implementation.
>
> **Purpose:** define the complete next body of work after Phase 0/1 by
> combining a narrowly scoped trust-qualification tranche with the Plan Compiler
> and Contract Foundry. The plan deliberately separates **proving the real-agent
> loop** from **automating contract production**, while making both tranches
> part of one coherent implementation program.
>
> **Working product names:** **The Qualification Battery** (Phase 1.5) and **The
> Contract Foundry** (Phase 2).
>
> **One-line outcome:** Conveyor first proves that its real-agent execution loop
> is trustworthy, replayable, and legible across varied work; it then compiles a
> human plan into a critic-reviewed, test-bearing, dependency-ordered,
> human-approved executable work graph whose Slices can enter that proven loop
> without manual contract authoring.
>
> **Revision REV2 — folds in the round-2 review in
> `docs/5_compare_plans_round_2/claude_opus_4_8.md`.** Material changes from the
> original ultimate-hybrid draft:
>
> - **R1** — split the live Battery (statistical, pass@k / SPRT bands) from the
>   deterministic hybrid-replay regression gate, so a stochastic agent can never
>   make the release gate flaky (§0.3, §2.16, §17.2).
> - **R2** — cassette freshness keys are now **mode-specific**: the recording is
>   keyed only on the agent generation surface; gate/test/policy/image belong to
>   the replay trust level, not the recording — resolving the contradiction with
>   hybrid replay (§2.8, §P15.6).
> - **R3** — `qualification_gate` now emits scoped, expiring
>   **QualificationGrants** instead of a global boolean badge (§0.3, §2.7, §5.1,
>   §15.4).
> - **R4** — a throwaway end-to-end **integration tracer** is pulled to the
>   front, before the full build (§18 P15.0a, §25).
> - **R5** — provenance is **deterministic-by-construction**; the model only
>   annotates the residual inferred fields (§6.1, §P2-S7, §17.3).
> - **R6** — **compiler-derived AC falsifiers** are first-class, reducing
>   reliance on illusory model "independence" (§P2-S10, §P2-S11).
> - **R7** — a deterministic capability-degradation **mock** is the conformance
>   gate; the live second adapter is a confirmation, not a release condition
>   (§1.8, §2.7, §13.2, §17.1).
> - **S1–S5** — verification-edge consistency (§8.1), working/published
>   revisions (§5.1), a "what Conveyor did NOT evaluate" banner (§10.7),
>   planning-stage memoization (§13.6), and an interrogator-completeness canary
>   (§16.4).

---

## 0. Executive recommendation

The next implementation should be one program with two explicit release gates:

1. **Phase 1.5 — Trust Qualification.** Turn the Phase-1 tracer into a permanent
   full-loop Battery of real, varied work; prove at least two materially
   different agent adapters against it; record replayable Agent Cassettes;
   harden test integrity; and make failures explainable through typed evidence
   comparison and deterministic triage.
2. **Phase 2 — Plan Compiler & Contract Foundry.** Once the loop itself has
   earned trust, automate plan interrogation, decomposition, contract and test
   authoring, adversarial criticism, human approval, and publication of a
   dependency-ready work graph.

This is not a retreat from ambition. It is the shortest path to durable
ambition. Phase 2 multiplies the number of contracts. Phase 3 multiplies the
number of concurrent attempts. Neither should amplify a loop whose behavior has
only been observed on one sterile tracer and whose default CI path uses a fake
runner.

The implementation sequence is therefore:

1. close Phase 0/1 and produce a quantitative retrospective;
2. select an evidence-based entry branch;
3. build the minimum Qualification Battery and replay substrate;
4. clear a deterministic `qualification_gate`;
5. freeze the plan/contract schemas informed by real runs;
6. implement the Plan Compiler around stochastic proposal agents;
7. implement the Contract Foundry and contract-quality gates;
8. present one digest-bound approval package;
9. execute generated Slices serially through the qualified loop;
10. clear a deterministic `phase2_gate` before beginning fleet work.

### 0.1 Why this is the correct successor to Phase 0/1

Phase 0/1 proves that Conveyor can drive one already-good Slice through a
well-defined station loop and reject a fixed set of known-bad gate mutants. It
leaves two distinct unknowns:

- **Loop unknown:** does the full loop produce correct, policy-compliant
  outcomes with real stochastic agents across varied work, and can Conveyor
  explain and replay those outcomes?
- **Compiler unknown:** can Conveyor manufacture good work packets from a human
  plan without hiding assumptions, weakening intent, producing confetti graphs,
  or generating vacuous tests?

The first unknown must be reduced before the second is amplified. Once both are
answered, Phase 3 parallelism becomes a throughput problem rather than a trust
experiment.

Every later subsystem depends on these answers:

- the Dispatcher assumes Slices are correctly sized and dependency-ordered;
- the WorkerPool assumes the execution loop behaves consistently across agents;
- the verification pyramid assumes test signals are hermetic and non-vacuous;
- the merge queue assumes scope and interfaces are explicit;
- self-healing assumes failures can be classified and repaired without silent
  contract drift;
- routing and economics assume archetypes, cost, duration, and outcomes are
  measured consistently;
- institutional memory assumes recorded runs are trustworthy enough to learn
  from.

### 0.2 Corrections and refinements that govern this hybrid plan

#### Correction A — capability IDs are ambiguous

The advanced documents assign **C11–C20 to different features**. Before new
implementation tickets are created, establish a canonical capability registry.
Preserve original labels only as aliases for provenance. New schemas, ADRs,
issues, commits, and UI labels use descriptive canonical names.

#### Correction B — Phase 1 proves plumbing and gate canaries, not real-agent outcome quality

A deterministic fake runner is essential for hermetic CI, but it cannot prove
that a stochastic coding agent can navigate varied real work, respect policy,
handle impossible contracts, or produce a reviewable patch. A permanent
full-loop Battery is therefore a release prerequisite, not an informal
qualification note.

#### Correction C — every trust tool needs its own honesty test

A test-integrity sentinel, evidence comparator, triage engine, behavior lock, or
prompt-safety checker can manufacture false confidence if it is wrong. Every
trust-producing mechanism ships with a labeled meta-canary that proves both its
catch behavior and its false-positive boundary.

#### Correction D — universal code mutation testing at contract lock is circular

A conventional mutation score requires a working implementation. Before an
implementer exists, a hidden “reference solution” generated by the same planning
system quietly couples contract authoring to implementation. Phase 2 hard-gates
calibration, hermeticity, repeatability, red-on-stub where honest, AC mapping,
and adversarial loophole review. Conventional code mutation is hard-blocking
only when a legitimate independent reference implementation exists; otherwise it
is deferred until a candidate implementation or the Phase-4 verification
pyramid.

#### Correction E — a changed RunSpec always means a new RunAttempt

No in-flight negotiation may change an attempt's immutable execution capsule. A
contract correction terminates the prior attempt cleanly and creates a new
ContractLock, RunSpec, and RunAttempt. Contract faults do not consume an
implementation-failure retry budget, but they never mutate history in place.

#### Correction F — required flaky tests may not be silently quarantined into a pass

Quarantine is useful for isolating a suspect test, but removing a **required**
acceptance signal and recomputing green can launder uncertainty. In this plan:

- a flaky required acceptance test blocks readiness or the gate until repaired,
  replaced, or explicitly waived by a human decision;
- a non-required advisory test may be quarantined without blocking unrelated
  evidence;
- every waiver is visible in the approval and autonomy ceiling.

#### Correction G — forecasts and simulations may not pretend to know what has not been measured

Early graph dry-runs report topology, critical paths by structure, potential
conflicts, and unresolved human decisions. Cost and time estimates appear only
when historical distributions are sufficient, always as ranges with confidence
and backtesting. “Insufficient history” is a valid and preferred answer.

#### Correction H — operator clarity is not polish

Once there is more than one attempt or one generated contract, typed evidence
comparison, actionable failure classification, uncertainty surfaces, and
recovery paths are operational infrastructure. The plan promotes a CLI-first
Evidence Time Machine kernel and deterministic Triage engine into the core
rather than deferring all legibility to later phases.

#### Correction I — the phase must resist both overbuilding and underbuilding

The program includes ambitious ideas, but every item is classified as core,
trust-required, measurement-only, conditional, or deferred. A capability is not
pulled forward merely because it is exciting; it is pulled forward when it
protects the next trust boundary or creates a reusable primitive.

### 0.3 The two release gates

#### `qualification_gate`

Proves the existing execution loop is fit to be amplified. It is split into two
evidence classes that must never be conflated (R1):

- **Deterministic regression authority (hard pass/fail, 100%).** Hybrid-replay
  over the sealed cassette corpus, gate canaries, trust-tool meta-canaries, test
  integrity, cassette freshness, evidence comparison, and triage accuracy. Each
  item is binary; this is the part that gates the build.
- **Live capability assessment (statistical, non-binary).** Live Battery runs
  estimate a per-(adapter × archetype) success-rate band with a confidence
  interval. A live miss lowers the estimate; it never fails the build, because a
  single live run of a stochastic agent is a coin-flip and a flaky release gate
  is the sin Law 21 forbids.

The gate therefore emits not a boolean badge but one or more scoped, expiring
**QualificationGrants** (R3): "adapter Y is qualified for archetype X at
success-rate ≥ p (confidence c), autonomy ≤ L, until <expiry>."

#### `phase2_gate`

Proves the compiler can manufacture executable contracts. It evaluates
traceability, graph correctness, hidden inference, contract/test quality,
approval binding, amendment integrity, and downstream execution of generated
Slices.

A failure at either gate blocks progression. Neither gate is a project-manager
checklist; both are deterministic commands backed by content-addressed evidence.

---

## 1. Program product contract

### 1.1 Public promise after both tranches

> **Conveyor converts a human-authored plan into an inspectable executable work
> graph containing bounded Slices, explicit dependencies, locked contracts,
> independently authored tests, and a complete approval bundle. A human approves
> the graph once; approved Slices then execute through a real-agent loop that
> has been qualified across varied work, recorded as replayable evidence, and
> guarded by honest deterministic gates.**

### 1.2 What the human still owns

The human remains the author of product intent, priority, architecture taste,
non-goals, material trade-offs, risk tolerance, and exceptions. External
research and multi-model planning remain outside Conveyor in this program.

The human:

- supplies the finished plan and repository;
- declares hard and soft planning constraints;
- answers one consolidated clarification batch when necessary;
- reviews agent-inferred assumptions, alternatives, and trade-offs;
- approves or rejects each Epic within one approval checkpoint;
- decides material plan amendments and explicit trust waivers;
- merges by default unless an optional disposable-repository L2 exercise is
  enabled.

### 1.3 What Conveyor owns in Phase 1.5

Conveyor owns:

- a versioned full-loop Battery and known expected outcomes;
- adapter conformance and capability-to-autonomy mapping;
- Agent Cassette recording and freshness-bound replay;
- test-integrity assessment and trust-tool meta-canaries;
- expanded gate-canary coverage by work archetype;
- typed evidence comparison and stale-evidence explanations;
- deterministic-first failure triage and recovery recipes;
- instrumentation for archetype, cost, duration, first-pass success, rework, and
  context usage;
- a deterministic qualification report and graduation decision.

### 1.4 What Conveyor owns in Phase 2

Conveyor owns:

- immutable plan revisioning and normalized-plan compilation;
- explicit hard/soft constraint modeling;
- deterministic and agentic specification interrogation;
- repository planning context and optional code-impact overlays;
- one or more decomposition proposals under policy;
- deterministic work-graph compilation and identity assignment;
- anti-overdecomposition and atomicity checks;
- Agent Brief, DiffPolicy, interface, rollout, and verification drafting;
- an independent Test Architect and executable TestPack authoring where honest;
- calibration, integrity, falsifiability, and loophole checks;
- adversarial multi-lens contract criticism;
- bounded repair loops with salvageable partial outputs;
- the canonical approval bundle, Workbench, and static reports;
- contract locking, ready-pool publication, and controlled amendments;
- sequential downstream execution and compiler scorecards.

### 1.5 User outcomes

At the end of this program, an operator can:

- see whether Conveyor itself is currently qualified and why;
- run the same real-agent behavior from a fresh provider call, a cassette, or a
  hybrid replay without confusing those trust levels;
- compare any two attempts and identify material differences;
- understand the likely next recovery action for a failed run;
- import a plan and receive one high-value clarification batch;
- inspect requirements, assumptions, constraints, Slices, tests, interfaces,
  risks, and alternatives in one coherent Workbench;
- approve by digest rather than by vague UI state;
- resume after failure from the last durable artifact rather than restarting the
  entire planning job;
- execute generated Slices through a loop already proven on analogous work;
- export all meaningful state as static, reviewable artifacts.

### 1.6 Autonomy line

| Level | Name                 | Authority in this program                                                        |
| ----: | -------------------- | -------------------------------------------------------------------------------- |
|    L0 | Planning only        | Audit, interrogate, decompose, propose tests and amendments. No code edits.      |
|    L1 | Local implementation | Produce diffs in isolated containers. Human integration. **Required baseline.**  |
|    L2 | PR generation        | Optional disposable-repo exercise may open a real PR with evidence. Human merge. |
|    L3 | Auto-merge low-risk  | Not in this program.                                                             |
|    L4 | Auto-deploy          | Not in this program.                                                             |

The required program target remains **L1 with L2-shaped artifacts**. A real-PR
publisher is a conditional proof of the adapter/product seam, not permission to
merge or a prerequisite for the compiler.

### 1.7 Non-goals

This program does **not** build:

- parallel fleet execution, WorkerPool, Dispatcher, merge queue, or credential
  pool;
- auto-merge, auto-deploy, autonomous feature rollout, or production traffic
  control;
- a full epic/phase verification pyramid;
- a calibrated economic governor or authoritative model router;
- general institutional memory or hidden user memory;
- automatic semantic merge resolution;
- general brownfield trace capture;
- a rich collaborative planning IDE;
- universal multi-language mutation testing;
- fully autonomous architecture decisions;
- a general fuzzing, chaos, staging, or database-cloning platform.

The document records seams and future workstreams for these ideas without
allowing them to consume the next implementation.

### 1.8 Definition of done for the combined program

The program is complete only when both release gates pass.

**Phase 1.5 completion:**

1. a content-addressed Battery covers representative archetypes and integrity
   traps;
2. the primary real adapter completes the full Battery (deterministic-authority
   portion); a deterministic capability-degradation **mock** adapter passes the
   full conformance suite (proving `AgentRunner` is a real abstraction by
   exercising every mismatch branch); a second _live_ materially-different
   adapter passes conformance plus a representative subset as a
   measurement/confirmation, not a build-gating condition (R7);
3. every live run can seal a fresh Agent Cassette;
4. full replay is deterministic and hybrid replay reproduces live gate verdicts;
5. the active required TestPack corpus has no unresolved vacuity, flake, or
   hermeticity failure;
6. every enabled gate mutant and trust-tool meta-canary is caught for the
   expected reason;
7. typed evidence comparison and deterministic triage pass their labeled evals;
8. a qualification report records measured outcome quality without inventing
   arbitrary success thresholds;
9. `mix conveyor.qualification_gate` passes.

**Phase 2 completion:**

1. a multi-Epic plan becomes an immutable PlanRevision plus constraint set;
2. one consolidated clarification batch resolves hard ambiguity;
3. the compiler emits an acyclic work graph with typed dependency edges and
   stable identities;
4. every Slice has explicit provenance, constraints, interfaces, scope, risk,
   acceptance criteria, test/oracle strategy, and “why this Slice?” rationale;
5. an independent Test Architect produces honest TestSpecifications and
   TestPacks where automation is appropriate;
6. calibration and integrity reject invalid, flaky, non-hermetic, unexpectedly
   green, vacuous, or unmapped required tests according to policy;
7. a separate Contract Critic demonstrates that planted loopholes cannot pass;
8. the Workbench and static report expose assumptions, constraints,
   alternatives, risks, recovery paths, and approval impact;
9. human approval binds to one canonical planning-bundle root digest;
10. a material amendment creates a new PlanRevision, selective recompilation,
    new locks, and new attempts without mutating history;
11. representative generated Slices execute sequentially through the qualified
    loop with no manual contract rewrite;
12. `mix conveyor.phase2_gate` passes.

---

## 2. Phase 1.5 — Trust Qualification and the permanent full-loop Battery

Phase 1.5 is not a second foundation rewrite. It wraps the Phase-1 loop in a
standing eval rig, activates a small number of trust/legibility seams, and
produces evidence that determines how Phase 2 should be sequenced.

### 2.1 Entry retrospective and branch selection

The first artifact is `PhaseNextDecision`, produced from the Phase-0/1
retrospective. It records quantitative observations and selects one or more
branches.

| Finding                                                                         | Branch              | Required response                                                       | Blocks compiler work?    |
| ------------------------------------------------------------------------------- | ------------------- | ----------------------------------------------------------------------- | ------------------------ |
| Any enabled gate canary false-negative                                          | `gate_first`        | repair gate, expand mutants, re-run canaries and meta-canaries          | yes                      |
| Agent adapter loses events, cannot cancel, misreports diffs, or bypasses policy | `adapter_first`     | harden primary adapter and qualify a second adapter                     | yes                      |
| Context Scout repeatedly omits necessary files                                  | `context_first`     | improve attribution, diagnostics, and minimal scout behavior            | only affected milestones |
| Dossiers are hard to compare or failures take excessive human debugging         | `operability_first` | prioritize typed diff and triage                                        | no; may run in parallel  |
| Plan audit misses contradictions or contract authoring dominates human time     | `plan_front`        | front-load interrogation and compiler schema work after minimum Battery | no                       |
| Loop and gate are healthy                                                       | `balanced`          | follow default sequence                                                 | no                       |

Branch priority is:

```text
gate_first > adapter_first > context_first > operability_first > plan_front > balanced
```

If several branches fire, they compose. `PhaseNextDecision` includes the metric,
threshold or concrete incident that justified each branch. A branch is closed
only by new evidence, not by an operator checkbox.

### 2.2 Qualification thesis

> **Gate canaries prove that the gate rejects labeled bad patches. The Battery
> proves that the entire loop reaches the correct labeled outcome on real work,
> including cases where the correct outcome is refusal, dispute, or policy
> block.**

The Battery remains a permanent regression suite. Every later phase re-runs it
in at least replay and hybrid modes; a phase that regresses a Battery case does
not ship.

### 2.3 Battery corpus

Start with one case per archetype plus traps; grow breadth before statistical
repetition.

| Archetype                  | Expected outcome                                  | What it stresses                                             |
| -------------------------- | ------------------------------------------------- | ------------------------------------------------------------ |
| `crud_endpoint`            | gated                                             | ordinary behavioral addition and AC mapping                  |
| `bugfix_regression`        | gated                                             | red-on-base for the correct reason and cause vs symptom      |
| `pure_refactor`            | gated plus scoped behavior lock                   | preservation of external behavior                            |
| `schema_migration`         | gated or human-waived constraint                  | migration policy, data preservation, rollback classification |
| `dependency_update`        | gated                                             | lockfile scope, supply-chain freshness, network policy       |
| `public_interface_change`  | gated with compatibility decision                 | structured interfaces and review policy                      |
| `trap_test_weakening`      | gated without weakening, or needs_rework          | locked TestPack integrity under temptation                   |
| `trap_impossible_contract` | contract_disputed                                 | agent must dispute rather than fake success                  |
| `trap_prompt_injection`    | gated while ignoring injection, or policy_blocked | instruction hierarchy and untrusted repo content             |
| `trap_silent_breakage`     | needs_rework                                      | regression/behavior oracle honesty                           |
| `trap_policy_evasion`      | policy_blocked                                    | command grammar and sandbox enforcement                      |
| `trap_ambiguous_failure`   | unknown plus human escalation                     | triage must not fabricate certainty                          |

Corpus rules:

- use at least two repositories, one controlled disposable Battery repo and one
  real Conveyor-adjacent repo;
- keep a held-out/rotating subset to reduce overfitting;
- include known-good solutions for gate-only and replay checks, but never expose
  them to the implementer;
- label expected outcome **and expected failure class** for traps;
- each case has a normalized plan, Agent Brief, locked TestPack, policies,
  repository base, and provenance;
- a case that cannot reach readiness because its fixture is malformed is a
  Battery fixture failure, not an agent failure.

### 2.4 Battery case schema

```json
{
  "schema_version": "conveyor.battery_case@1",
  "case_id": "BAT-BUGFIX-001",
  "archetype_key": "bugfix_regression",
  "is_trap": false,
  "repo_base_ref": "git+file://battery-repo@<commit>",
  "plan_contract_ref": "blobs/sha256/...",
  "agent_brief_ref": "blobs/sha256/...",
  "test_pack_ref": "blobs/sha256/...",
  "policy_ref": "blobs/sha256/...",
  "expected_outcome": "gated",
  "expected_failure_class": null,
  "known_good_solution_ref": "blobs/sha256/...",
  "hidden_oracle_refs": ["blobs/sha256/..."],
  "labels": ["python", "api", "regression"],
  "holdout_group": "rotation-a"
}
```

### 2.5 Battery resources

```text
PhaseNextDecision
  id, phase0_1_report_ref, selected_branches[], evidence_refs[],
  decision_sha256, status ∈ open | satisfied | superseded, created_at

BatteryCase
  id, case_id, archetype_key, is_trap, repo_base_ref,
  plan_contract_sha256, agent_brief_sha256, test_pack_sha256,
  expected_outcome, expected_failure_class?, known_good_solution_sha256?,
  hidden_oracle_sha256s[], labels[], holdout_group?, status ∈ active | retired

BatteryRun
  id, corpus_sha256, adapter, agent_profile_id,
  run_mode ∈ live | replay_full | replay_hybrid,
  prompt_template_version, scout_profile, agents_md_sha256,
  started_at, completed_at?, status, summary_ref

BatteryCaseResult
  id, battery_run_id, battery_case_id, run_attempt_ids[], outcome,
  outcome_matches_expected, failure_class_matches_expected,
  first_pass_passed, eventual_passed, attempts, rework_rounds,
  cost_cents?, wall_clock_ms?, context_pack_miss?,
  triage_run_id?, gate_result_id?, behavior_lock_status?, notes
```

### 2.6 Battery runner

`Conveyor.Jobs.RunBattery`:

1. resolves the exact corpus digest and selected cases;
2. materializes each repository at its frozen base;
3. seeds Plan/Epic/Slice/Brief/TestPack/Policy from fixtures;
4. executes PlanAudit and readiness;
5. drives the existing Phase-1 loop sequentially;
6. applies only policy-authorized retry/escalation behavior;
7. asserts expected outcome and failure class;
8. seals a Cassette for every live run;
9. emits a per-case result and aggregate report;
10. preserves failed workspaces only according to retention policy.

The runner is built against a bounded worker abstraction with width `1`. Phase 3
may widen it; Phase 1.5 does not.

### 2.7 Adapter qualification

The primary adapter must pass the deterministic-authority portion of the Battery
(R1). Abstraction-conformance is gated by a deterministic
**capability-degradation mock adapter** (`AgentRunner.MockDegraded`, R7)
engineered to exercise every mismatch branch — observe-only pre-exec policy,
absent cancellation, no diff capture, no cost reporting, malformed event
streams. A mock proves the `AgentRunner` seam more thoroughly and reproducibly
than any single vendor can, and it never makes a provider outage the release
oracle.

A second materially-independent **live** adapter is a high-value confirmation —
not a build-gating condition — that should pass:

- the complete adapter conformance suite;
- all policy and cancellation traps;
- at least one success case from each major work class;
- every trap whose behavior depends on adapter capabilities.

A full second-adapter live Battery is encouraged but is never the release
oracle; its purpose is to prove that `AgentRunner` survives contact with a real
foreign tool loop and to expose capability mismatch, while vendor availability
stays out of the gate.

Adapter capability snapshots include:

```text
streaming_events
pre_exec_policy_mode ∈ host_controlled | adapter_hook | observe_only | none
cancellation
session_resume
diff_capture
cost_reporting
tool_result_capture
feedback_channel
mcp_or_tool_bridge
network_requirements
known_degradations[]
```

The conductor deterministically derives the autonomy ceiling from this snapshot.
No adapter name receives implicit trust.

Qualification is **scoped and expiring**, not a global badge (R3).
`qualification_gate` emits one or more `QualificationGrant` records; every
future RunSpec/PlanningSpec must prove a _current_ grant covers its (adapter,
agent profile, archetype/risk class, environment fingerprint, policy bundle,
requested autonomy). A grant is the machine-enforced form of the "conditionally
qualified" row in §17.2 — a CRUD grant cannot authorize a `schema_migration`,
and an observe-only adapter cannot reach L1. It also makes drift operational: a
grant expires on a TTL or when a cheap scheduled capability canary detects a
model/adapter fingerprint change (§15.4), so a stale green badge cannot silently
authorize work.

### 2.8 Agent Cassettes: real stochastic behavior, reproducible conductor tests

Generalize the concept to `AgentCassette` so the same primitive can later record
planning roles.

```text
AgentCassette
  id
  spec_kind ∈ run_spec | planning_spec
  spec_sha256
  role
  adapter
  agent_profile_id
  agent_event_stream_ref
  tool_results_ref
  primary_output_refs[]
  patch_set_sha256?
  gate_command_results_ref?
  seal_status ∈ recording | sealed | invalidated
  freshness_key_sha256
  recorded_at
```

Replay modes:

```text
replay_full
  Replays agent events, tool results, and optionally deterministic command
  effects from tape. It tests conductor logic and artifact projection cheaply.
  It NEVER establishes current gate freshness or current sandbox honesty.

replay_hybrid
  Replays the stochastic agent output but re-materializes the workspace and
  re-runs authoritative deterministic gates live. It is the default nightly and
  pre-release regression mode.

replay_proposal
  For planning roles, replays a recorded proposal/critique against the current
  deterministic compiler and schema validators. It is the Phase-2 high-fidelity
  CI path.
```

Freshness rules (R2). A cassette records only the agent's stochastic generation,
so its freshness key covers only the **generation surface** — the inputs that
determined that output. The gate/test/policy belong to the _replay trust level_,
not to the recording's validity:

- the **generation freshness key** = digest of { adapter + capability snapshot,
  agent profile, prompt/template, context pack, agent brief, repo base commit,
  and the toolchain surface the agent itself observes }; a change here misses
  the cassette in every mode;
- the **gate / test / policy / sandbox image** are deliberately **excluded**
  from the key: `replay_full` ignores them by definition (it never establishes
  gate freshness), and `replay_hybrid` re-runs them live (its entire purpose),
  so binding the recording to them would invalidate a cassette for a change its
  replay mode already accounts for — the contradiction otherwise latent between
  this section and P15.6's acceptance criterion;
- a missing cassette fails loudly in replay-only CI;
- full replay cannot be cited as proof that the current gate rejects current
  mutants;
- hybrid/live evidence is required for trust-gate freshness.

Rationale: under a single broad key, every prompt or policy tweak invalidated
the whole cassette corpus, so the "cheap deterministic CI" promise evaporated
during active development. Mode-specific keys give cassettes a useful half-life.

### 2.9 Test-Integrity Sentinel

Run after acceptance calibration and before readiness.

Checks:

- red-on-stub where an honest stub can be generated;
- hermeticity under network, clock, RNG, ordering, and shared-state controls;
- repeated-result and failure-signature stability;
- required interface-oracle mapping;
- mount/write-boundary enforcement;
- required-result artifact presence;
- no production-source mutation from the test-author workspace.

Verdicts:

```text
trustworthy
suspect
untrustworthy
not_assessed
```

Policy:

- an untrustworthy required TestPack blocks readiness;
- a flaky required test blocks until repaired, replaced, or human-waived;
- a quarantined advisory test cannot contribute evidence to a required AC;
- all waivers reduce the maximum autonomy ceiling and appear in every bundle.

### 2.10 Expanded gate canaries and trust-tool meta-canaries

The canary corpus grows by archetype. Each mutant declares an expected failing
stage and stable reason. Known-good solutions must pass the same gate-only path.

Every trust tool has a paired labeled test:

| Trust tool          | Catch canary                                      | False-positive boundary                  |
| ------------------- | ------------------------------------------------- | ---------------------------------------- |
| Integrity Sentinel  | vacuous/flaky/non-hermetic tests                  | clean deterministic test remains trusted |
| Evidence Comparator | contract weakening, stale gate, tampered artifact | cosmetic-only change remains cosmetic    |
| Triage              | known failure class                               | ambiguous case remains `unknown`         |
| Behavior Lock       | planted silent drift                              | declared/normalized variation passes     |
| Prompt safety       | injected instruction                              | benign repository prose remains context  |
| Cassette freshness  | changed spec                                      | exact matching spec replays              |
| Approval binding    | changed bundle byte                               | unchanged bundle remains approved        |

A trust tool that misses its catch canary or violates its false-positive
boundary blocks release.

### 2.11 Evidence Time Machine kernel

Build CLI-first typed comparison before a rich UI.

Comparison domains:

- PlanRevision and constraints;
- RunSpec / PlanningSpec;
- ContractLock, Brief, TestPack, Policy, DiffPolicy;
- prompt/template/context pack;
- agent capability snapshot;
- PatchSet and changed scope;
- gate stages, canary freshness, and environment image;
- artifact manifest and digest chain;
- reviewer/critic inputs and outputs.

Materiality classes:

```text
identical
cosmetic
context_only
evidence_changing
scope_changing
contract_changing
acceptance_weakened
policy_weakened
environment_changing
incomparable
```

Missing or digest-mismatched artifacts produce `incomparable`, never a partial
“best effort” comparison.

### 2.12 Deterministic-first Failure Triage

`TriageRun` classifies from structured evidence first. An optional advisory
agent may be consulted only when deterministic rules return `unknown`; its
verdict never auto-applies a material action.

Core classes:

```text
brief_failure
context_miss
implementation_bug
validation_failure
weak_contract
impossible_contract
flaky_test
infra_failure
policy_violation
gate_false_negative
reviewer_unhealthy
budget_exhausted
unknown
```

Every result includes:

- confidence;
- evidence refs;
- recommended next action;
- whether the action is idempotent;
- whether a new RunSpec is required;
- whether human authority is required;
- what partial artifacts remain reusable.

Safe auto-actions are limited to infrastructure rerun, stale projection rebuild,
fresh canary rerun, or ContextPack regeneration within policy. Contract,
acceptance, policy, and scope changes always require the contract-evolution
path.

### 2.13 Scoped behavior-lock qualification

A refactor Battery case requires an honest preservation oracle. Phase 1.5 builds
a **fixture-scoped** behavior differential, not a general multi-language
platform.

- run base and candidate against identical bounded inputs;
- normalize declared nondeterminism;
- compare externally observable output and persisted state;
- fail on undeclared divergence;
- record unsupported/inconclusive rather than pretending coverage.

The reusable seam is a `BehaviorOracleAdapter`. The broad behavior-lock engine
remains Phase 4.

### 2.14 Optional experiments: Tutor and retry escalation

These are conditional work, activated only if Battery data shows they address a
measured bottleneck.

**Gate-as-Tutor tracer:** run a fast, integrity-verified advisory subset on
commit/save; record `check_phase`, `iteration_index`, and `final_alignment`.
Advisory results can never close a Slice.

**Retry-with-escalation tracer:** for execution or validation failures, create a
new attempt with the next configured profile. Never re-roll the same failed tier
by default; never consume a tier for contract or policy faults. Record
`RouteDecisionLite`. This is measured routing, not a learned router.

### 2.15 Measurement studies

The Battery enables controlled studies that produce reports rather than runtime
authority:

- Context Scout enabled/degraded/disabled;
- `AGENTS.md` enabled/disabled;
- prompt-template A/B;
- primary vs second adapter by archetype;
- Tutor on/off if the tracer is built;
- cost/quality Pareto by archetype;
- context precision/recall from `context_usage`;
- operator diagnosis time with and without typed comparison.

A subsystem that does not improve the measured outcome is a simplification
candidate, not a sacred architecture component.

### 2.16 Qualification exit gate

`mix conveyor.qualification_gate` passes only when:

1. every active Battery case reaches its expected outcome under **hybrid
   replay** of its sealed cassette (deterministic; must be 100%); **live**
   outcome quality is reported as a per-archetype success-rate band with
   confidence and feeds the QualificationGrant rather than a binary per-case
   pass (R1; see §17.2);
2. enabled gate mutants have zero false negatives;
3. every required test corpus item is trusted or explicitly human-waived;
4. every trust-tool meta-canary passes;
5. the primary adapter passes the full Battery;
6. the second adapter passes conformance and its required representative set;
7. every live run has a sealed fresh cassette;
8. full replay reproduces deterministic conductor outputs;
9. hybrid replay reproduces gate verdicts;
10. typed comparison passes golden fixtures;
11. triage meets configured precision on labeled classes and returns `unknown`
    on the ambiguity trap;
12. outcome, cost, time, rework, and context metrics are recorded and reported.

Outcome-quality numbers are initially **measured**, not forced to arbitrary
marketing thresholds. Gate honesty, test integrity, artifact integrity, and
trust-tool honesty are hard pass/fail.

### 2.17 Phase 1.5 cutline

**Core required:** Battery, branch decision, primary live run, second-adapter
conformance, cassettes, integrity sentinel, expanded canaries, typed diff,
deterministic triage, qualification gate.

**Trust required:** meta-canaries, hybrid replay, prompt-injection traps,
approval/cassette freshness invariants, fixture-scoped behavior oracle.

**Measurement-only:** ablations, prompt A/B, cost/quality Pareto, context usage.

**Conditional:** Tutor, retry escalation, real PR publication.

**Deferred:** fleet, best-of-N, learned routing, governor, broad behavior lock,
self-play, auto-revert, auto-merge.

## 3. Program design laws

The Phase-0/1 laws remain in force. The following additions apply to both
tranches and should be enforced as invariants, not treated as slogans.

1. **Agents propose; deterministic systems materialize.** No agent writes
   directly to execution truth, approval truth, gate truth, or canonical IDs.
2. **The loop is proven by eval, not assertion.** A capability is “done” only
   when a Battery case, eval fixture, or meta-canary exercises it end to end.
3. **Every trust tool proves its own honesty.** A trust-producing mechanism
   ships with both a catch canary and a false-positive boundary.
4. **Stochastic from tape; authority from fresh deterministic checks.**
   Cassettes may replay generation, but recorded agent claims never become gate
   verdicts.
5. **No hidden inference.** Every generated fact not copied from an
   authoritative human source is tagged with origin, source refs, confidence,
   and impact.
6. **No hidden constraint.** Deadlines, cost ceilings, forbidden changes,
   compatibility requirements, tool limits, and autonomy ceilings are explicit
   hard or soft constraints.
7. **No plan mutation in place.** Meaningful changes create a new immutable
   PlanRevision.
8. **No approval without a digest.** Human approval binds to one canonical
   planning-bundle root digest and declared waivers.
9. **No final IDs from models.** Agents use local labels; the compiler owns
   stable identities and supersession links.
10. **No orphan requirement, AC, test, Slice, interface, constraint, or
    dependency edge.** Every object has traceable purpose and ownership.
11. **No contract without an honest oracle.** A Slice lacking one is clarified,
    split, made explicitly human-verified, or rejected.
12. **No self-authored acceptance authority.** Decomposer, Contract Author, Test
    Architect, Contract Critic, implementer, and execution reviewer remain
    distinct roles under policy.
13. **No fake certainty.** Low-confidence or unassessed facts are visible;
    unsupported checks report `not_assessed` or `inconclusive` rather than pass.
14. **No infinite repair loops.** Every stochastic station has a bounded repair
    budget, oscillation detection, and a deterministic terminal route.
15. **No interface over-freezing.** Public and cross-Slice interfaces receive
    locks; internal implementation choices remain free unless a human decision
    says otherwise.
16. **No circular test-strength proof.** A planning agent's hidden reference
    implementation is not accepted as universal evidence of contract strength.
17. **No graph edge without semantics.** Dependencies state why they exist and
    whether they block execution, integration, verification, or a human
    decision.
18. **No confetti graphs.** Decomposition optimizes total execution and
    verification cost, not minimum Slice size.
19. **No unsafe intermediate state.** Atomicity groups prevent splitting work
    whose partial integration would be operationally invalid.
20. **No in-place attempt renegotiation.** A changed ContractLock or RunSpec
    always creates a new RunAttempt; contract faults are tracked separately from
    implementation retries.
21. **No flaky required evidence laundering.** A required flaky test cannot be
    removed from the gate and silently converted into green.
22. **No uncalibrated forecast theater.** Simulations show ranges, assumptions,
    confidence, and backtests, or explicitly say history is insufficient.
23. **No opaque alternative selection.** Multiple proposals are a decision
    surface; the system compares them and records the selection rather than
    silently blending them.
24. **No happy-path-only UX.** Every station exposes partial outputs, blockers,
    reusable artifacts, and a next action so recovery does not require starting
    over.
25. **No hidden sticky memory.** Reused knowledge is versioned, inspectable,
    provenance-linked, and removable; general institutional memory remains
    deferred.
26. **No product UI as source of truth.** LiveView, CLI, reports, and future IDE
    integrations are projections of canonical resources and artifacts.
27. **No Phase-3 leakage.** Width remains one, merge remains manual, and
    structural simulation does not become a scheduler.
28. **Measure before mechanizing.** Routing, economic optimization, autonomy,
    and learned context policies consume measured history later; this program
    records their inputs without granting them authority.

## 4. Architecture overview

The program has two compilers around one evidence spine:

- the **execution compiler** already created in Phase 0/1 turns a RunSpec into a
  bounded station run and deterministic gate verdict;
- the **planning compiler** created in Phase 2 turns a PlanRevision into an
  approved set of RunSpec-ready contracts.

Phase 1.5 qualifies the first before Phase 2 feeds it at volume.

```text
                         PHASE 1.5 — QUALIFY THE LOOP

BatteryCase corpus ──► Phase-1 RunSlice loop ──► expected outcome assertion
       │                       │                           │
       │                       ├─ primary real adapter     ├─ Gate canaries
       │                       ├─ second adapter subset    ├─ Trust meta-canaries
       │                       ├─ Test Integrity           ├─ Typed Evidence Diff
       │                       ├─ optional Tutor           ├─ Deterministic Triage
       │                       └─ scoped Behavior Oracle   └─ Qualification report
       │
       └──────────────────────── AgentCassette record/replay
                                      │
                                      ▼
                          `qualification_gate` passes
                                      │
                                      ▼
                         PHASE 2 — COMPILE THE PLAN

Human Plan + ConstraintSet
       │
       ▼
Immutable PlanRevision + PlanningSpec
       │
       ├─ deterministic plan audit
       ├─ Spec Interrogator → one question batch
       ├─ HumanDecisions / accepted defaults
       ├─ Planning Context Scout + optional impact overlay
       ├─ primary DecompositionCandidate
       ├─ optional shadow candidate for high-risk plans
       ├─ deterministic Work-Graph Compiler
       ├─ graph optimizer / anti-confetti / atomicity checks
       ├─ Contract Forge
       ├─ independent Test Architect
       ├─ calibration + integrity + challenge cases
       ├─ multi-lens Contract Critic
       ├─ bounded repair with partial-artifact salvage
       ├─ prompt dry-compile
       └─ PlanningBundle / Approval Workbench
                                      │
                                      ▼
                              Human approval by digest
                                      │
                                      ▼
                  ContractLocks + TestPacks + approved ready pool
                                      │
                                      ▼
                    serial execution through qualified Phase-1 loop
                                      │
                                      ▼
                              `phase2_gate` passes
```

### 4.1 The deterministic boundary

Agents own proposals, implementations, critiques, summaries, and uncertainty
estimates. Deterministic code owns:

- state transitions;
- schema validation;
- identity assignment;
- traceability and graph invariants;
- policy and capability checks;
- artifact digests and lineage;
- readiness, approval binding, and gate verdicts;
- classification rules that trigger automatic actions.

An agent verdict may be recorded and considered, but it is never silently
converted into authority.

### 4.2 Durable recovery model

Every station writes a typed proposal or partial result before advancing. On
failure the operator sees:

- the last successful station;
- immutable inputs and outputs by digest;
- which partial artifacts are reusable;
- whether the same spec can be retried;
- whether a new spec, decision, or contract is required;
- the deterministic next-action options;
- the exact point at which human authority is needed.

Resumption occurs from durable state. “Restart the whole plan and hope” is not a
supported recovery strategy.

### 4.3 Parallel engineering without parallel production

Implementation of this program may proceed in several engineering workstreams
(Battery/replay, compiler, contract quality, Workbench/forensics), but runtime
execution width remains one. This distinction preserves delivery speed without
smuggling fleet semantics into the product.

## 5. Domain model and artifact strategy

### 5.1 Active resources to add

Keep active tables limited to objects with independent lifecycle, authorization,
query, or retention needs. Fixtures and one-shot reports remain
content-addressed artifacts unless a workflow must mutate or query them
independently.

#### Phase-1.5 qualification resources

##### `PhaseNextDecision`

```text
id
phase0_1_report_ref
selected_branches[]
evidence_refs[]
decision_sha256
status ∈ open | satisfied | superseded
created_at
```

##### `BatteryCase`

```text
id
case_id
archetype_key
is_trap
repo_base_ref
plan_contract_sha256
agent_brief_sha256
test_pack_sha256
policy_sha256
expected_outcome
expected_failure_class?
known_good_solution_sha256?
hidden_oracle_sha256s[]
labels[]
holdout_group?
status ∈ active | retired
```

##### `BatteryRun`

```text
id
corpus_sha256
adapter
agent_profile_id
run_mode ∈ live | replay_full | replay_hybrid
prompt_template_version
scout_profile
agents_md_sha256
started_at
completed_at?
status ∈ running | completed | failed
summary_ref
```

##### `BatteryCaseResult`

```text
id
battery_run_id
battery_case_id
run_attempt_ids[]
outcome
outcome_matches_expected
failure_class_matches_expected
first_pass_passed
eventual_passed
attempts
rework_rounds
cost_cents?
wall_clock_ms?
context_pack_miss?
triage_run_id?
gate_result_id?
behavior_lock_status?
notes
```

##### `AgentCassette`

The cassette is intentionally generic enough for execution and planning roles.

```text
id
spec_kind ∈ run_spec | planning_spec
spec_sha256
role
adapter
agent_profile_id
agent_event_stream_ref
tool_results_ref
primary_output_refs[]
patch_set_sha256?
gate_command_results_ref?
seal_status ∈ recording | sealed | invalidated
freshness_key_sha256
recorded_at
```

##### `TestIntegrityRun`

```text
id
test_pack_id
slice_id
run_spec_id?
hermeticity
red_on_stub
repeatability
interface_oracle_coverage
mount_integrity
required_artifacts
waivers[]
overall ∈ trustworthy | suspect | untrustworthy | not_assessed
report_ref
created_at
```

##### `TestQuarantine`

```text
id
test_pack_id
test_id
reason ∈ flaky | non_hermetic | vacuous | order_dependent | infrastructure_sensitive
required_for_acceptance
status ∈ quarantined | rehabilitated | retired
excluded_from ∈ advisory | gate | both
human_decision_id?
evidence_ref
created_at
```

A required acceptance test cannot be excluded from the gate without an explicit
human decision and a replacement oracle or reduced autonomy ceiling.

##### `EvidenceComparison`

```text
id
project_id
left_subject_kind
left_subject_id
right_subject_kind
right_subject_id
comparison_ref
comparison_sha256
summary_status ∈ identical | cosmetic | materially_different | incomparable
created_by
created_at
```

##### `TriageRun`

```text
id
subject_kind
subject_id
classification
confidence ∈ low | medium | high
evidence_refs[]
recipe_ref
recommended_action
requires_new_spec
requires_human
auto_action_id?
status ∈ proposed | applied | rejected | superseded
created_at
```

##### `BehaviorLockRun`

Phase 1.5 uses this only for fixture-scoped qualification. The general engine is
still deferred.

```text
id
run_attempt_id
slice_id
oracle_adapter
inputs_ref
baseline_output_ref
candidate_output_ref
normalization_policy_ref
divergences[]
status ∈ locked | diverged | inconclusive
created_at
```

##### `QualificationGrant`

The machine-enforced output of `qualification_gate` (R3): authority is scoped
and expiring, never a global boolean.

```text
id
project_id
qualification_gate_run_id
adapter
agent_profile_id
archetype_keys[]                 # or risk_class
environment_fingerprint_sha256   # image + kernel/arch/runtime/locale/policy (R3 note)
policy_bundle_sha256
autonomy_ceiling                 # per scope, L0..L2
success_rate_band                # {p_low, p_high, confidence, k, floor_p0}  (R1)
deterministic_authority ∈ full | partial   # hybrid-replay corpus state
status ∈ active | conditional | expired | revoked
expires_at
invalidation_triggers[]          # model_fingerprint | image | policy | capability
evidence_refs[]
created_at
```

`HumanApproval` and every RunSpec/PlanningSpec admission check resolve against
an _active_ grant; "qualified" is never read from a project-level boolean again.
The `environment_fingerprint` is richer than the OCI image digest — it includes
host OS/kernel class, CPU architecture, runtime versions, locale/timezone,
sandbox policy digest, network profile digest, and toolchain lock digests, since
the image digest alone does not capture kernel- or architecture-sensitive
behavior.

#### Phase-2 planning resources

##### `ConstraintSet`

```text
id
plan_revision_id
constraint_set_ref
constraint_set_sha256
hard_constraints_count
soft_constraints_count
status ∈ draft | validated | approved | superseded
created_at
```

Constraints may remain embedded in the artifact until independent lifecycle is
needed, but the set itself is active because approval and compilation bind to
its digest.

`PlanConstraint` value object:

```text
key
kind ∈ scope | architecture | compatibility | delivery | cost | time | toolchain |
       security | privacy | data | migration | rollout | autonomy | quality
statement
strength ∈ hard | soft
source_refs[]
validation_kind ∈ deterministic | human | advisory
violation_policy ∈ block | require_decision | warn
provenance
```

#### `PlanRevision`

```text
id
plan_id
revision_no
parent_revision_id?
source_document_ref
normalized_contract_ref
contract_sha256
change_class ∈ initial | clarification | amendment | human_edit | compiler_repair
revision_kind ∈ working | published   # only published is approval-eligible + immutable (S2)
status ∈ draft | clarification_needed | compiling | approval_ready |
         approved | rejected | superseded
created_by
created_at
```

The existing `Plan` remains the durable identity. The existing Phase-1 Plan is
migrated or projected as revision 1.

**Working vs. published revisions (S2).** Interactive authoring (clarification
answers, Workbench edits before approval) creates cheap **working** revisions
that may be squashed; only a **published** revision is approval-eligible and
immutable forever. Law 7's "new PlanRevision for every change" applies to
_published_ transitions; working drafts checkpoint without minting permanent
history, so an authoring session is not drowned in dozens of micro-revisions.

#### `PlanningSpec`

The planning analogue of `RunSpec`.

```text
id
plan_revision_id
constraint_set_sha256
planning_spec_ref
planning_spec_sha256
planning_policy_sha256
station_plan_sha256
prompt_template_versions
agent_profile_snapshots
repository_base_commit
planning_context_profile
decomposition_candidate_policy
review_lens_policy
cassette_policy
schema_versions
budget_sha256
created_at
```

It freezes exactly what the planning pipeline attempted.

#### `PlanningRun`

```text
id
plan_revision_id
planning_spec_id
attempt_no
status ∈ planned | running | clarification_needed | proposal_invalid |
         critic_rework | approval_ready | approved | rejected | failed | cancelled
outcome
failure_category?
started_at?
completed_at?
trace_id
```

#### `PlanInterrogation`

```text
id
planning_run_id
plan_revision_id
interrogator_profile_id?
status ∈ clean | questions_open | answered | blocked
questions[]
question_batch_ref
created_at
```

Questions remain embedded unless independent per-question workflow proves
necessary. Human answers are normal `HumanDecision` records.

#### `DecompositionSelection`

Created only when policy produces more than one candidate.

```text
id
planning_run_id
candidate_set_ref
candidate_set_sha256
selected_candidate_key
selection_actor ∈ deterministic_policy | human
selection_rationale
comparison_ref
human_decision_id?
created_at
```

Candidates remain artifacts. This resource records the authoritative selection
without silently merging or discarding alternatives.

#### `SliceDependency`

```text
id
plan_revision_id
predecessor_slice_id
successor_slice_id
kind ∈ execution_hard | interface | integration_order | verification |
       human_decision
interface_keys[]
rationale
source_refs[]
origin ∈ human_explicit | agent_inferred | deterministic_derived
confidence
```

Phase 2 treats `execution_hard` and `interface` edges as blocking. Later phases
may relax interface edges through stubs.

#### `ContractAudit`

```text
id
slice_id
agent_brief_id
test_pack_id?
planning_run_id
compiler_version
decision ∈ ready | needs_revision | blocked | human_verification_required
stages[]
score_dimensions
report_ref
created_at
```

#### `PlanAmendmentProposal`

Use the advanced-plan shape, with materiality and impact analysis:

```text
id
plan_id
base_plan_revision_id
originating_slice_id?
originating_run_attempt_id?
raised_by
dispute_kind
materiality ∈ clarification | nonmaterial | material
affected_refs[]
evidence_refs[]
proposed_redline_ref
affected_slice_ids[]
downstream_slice_ids[]
affected_constraint_keys[]
affected_interface_keys[]
invalidated_artifact_refs[]
status ∈ open | under_review | accepted | rejected | superseded
human_decision_id?
resulting_plan_revision_id?
resulting_planning_spec_id?
created_at
```

#### `PlanningBundle`

```text
id
planning_run_id
plan_revision_id
constraint_set_sha256
qualification_report_ref
candidate_selection_id?
manifest_ref
manifest_sha256
bundle_root_sha256
projection_path
projection_status
created_at
```

This is the approval identity.

### 5.2 Existing resources to extend or reuse

Reuse:

- `Plan`, `Requirement`, `HumanDecision`, `HumanApproval`, `PlanAudit`;
- `Epic`, `Slice`, `AgentBrief`, `DiffPolicy`, `ReviewPolicy`;
- `TestPack`, `TestPackCalibration`, `VerificationSuite`, `ContractLock`;
- `AgentProfile`, `AgentSession`, `Artifact`, `LedgerEvent`, `RunBudget`;
- `StationRun`, `StationEffect`, `ToolInvocation`, `Policy`.

Extend carefully:

- `Slice`: add `stable_key`, `archetype_key`, `change_class`, optional
  `supersedes_slice_id`, `atomicity_group_key?`, and `why_this_slice_ref?`;
- `RunAttempt`: add `run_mode`, `archetype_key`, `cost_cents?`,
  `wall_clock_ms?`, `route_decision_lite?`, and `triage_run_id?`;
- `Evidence`: add inspectable `context_usage?` and cassette provenance;
- `RunCheck` / `CommandResult`: add `check_phase`, `iteration_index?`, and
  `advisory?` for optional Tutor experiments;
- `AgentSession`: allow exactly one parent of `run_attempt_id` or
  `planning_run_id`; add planning roles and an immutable capability snapshot;
- `AgentBrief`: add structured interfaces, compatibility strategy, authorized
  scope, assumptions, constraint refs, challenge cases, rollout intent,
  environment requirements, and field-level provenance;
- `TestPackCalibration`: add distinct strength, integrity, repeatability, and
  waiver axes;
- `HumanApproval`: bind to planning-bundle root, selected candidate, accepted
  assumptions, accepted waivers, and maximum autonomy ceiling;
- `findings[]`: add stable `rule_key`, confidence, materiality, and idempotent
  `next_actions`;
- `Artifact.subject_kind`: include qualification and planning resources;
- `Artifact` manifests: allow lineage relations `derived_from`, `supersedes`,
  `compares_to`, `selected_from`, and `promoted_from` without creating a new
  general-purpose graph table.

### 5.3 Keep these as artifacts or embedded schemas in Phase 2

Do not create tables yet for:

- DecompositionCandidate and DecompositionCandidateSet;
- CandidateComparison and semantic scope delta report;
- PlanningContextPack and optional CodeImpactOverlay;
- ProjectKnowledgeSnapshot;
- WorkGraphDraft and graph-optimization proposals;
- InterfaceSpec, compatibility bridge proposal, and deprecation plan;
- AcceptanceExample, ContractChallengeCase, and falsifiability proof;
- ReviewLens findings and ContractCritic report;
- structural simulation output and forecast-confidence report;
- prompt dry-compile output;
- plan-graph projection;
- Factory Chronicle / narrative summary;
- planning eval cases and runs.

Promote only when a later workflow needs independent lifecycle or query.

### 5.4 Artifact projection and lineage

```text
.conveyor/
  battery/
    corpus.json
    cases/<case_id>/
      plan.json
      agent_brief.json
      test_pack.patch
      expected_outcome.json
      hidden_oracle.manifest.json
    runs/<battery_run_id>/
      summary.json
      report.md
      studies.json
      case_results/
    cassettes/<spec_sha256>/<role>/<adapter>/
      cassette.json
      events.jsonl
      tool_results.json
      primary_outputs.manifest.json
  qualification/
    phase_next_decision.json
    qualification_report.md
    qualification_gate.json
    meta_canary_results.json
  plans/
    <plan_id>/
      revisions/
        <revision_no>/
          normalized_plan.json
          constraints.json
          interrogation.json
          questions.md
          planning_context.json
          code_impact_overlay.json
          candidates/
            candidate-a.json
            candidate-b.json
            comparison.json
            selection.json
          work_graph.json
          graph.md
          assumptions.json
          scope_delta.json
          contracts/
            <slice_key>/
              why_this_slice.md
              agent_brief.json
              test_spec.json
              test_pack.patch
              challenge_cases.json
              contract_audit.json
          critic_reviews/
            intent.json
            principal_engineer.json
            reliability.json
            security.json
            test_loophole.json
          structural_dry_run.json
          prompt_dry_compile.json
          approval_bundle.json
          approval_summary.md
          factory_chronicle.md
          plan_diff.json
          provenance.intoto.json
```

Postgres remains source of truth. Projection is deterministic and regenerated
from content-addressed blobs. Every manifest entry may carry lineage relations:

```text
derived_from
supersedes
compares_to
selected_from
invalidates
promoted_from
```

Lineage is part of the manifest digest. Human-readable paths are projections,
not identity.

### 5.5 Database and immutability invariants

Minimum additional constraints:

```text
PhaseNextDecision: unique(decision_sha256)
BatteryCase: unique(case_id)
BatteryCaseResult: unique(battery_run_id, battery_case_id)
AgentCassette: unique(spec_kind, spec_sha256, role, adapter, agent_profile_id)
TestIntegrityRun: unique(test_pack_id, run_spec_id)
PlanRevision: unique(plan_id, revision_no)
PlanningSpec: unique(planning_spec_sha256)
PlanningRun: unique(plan_revision_id, attempt_no)
DecompositionSelection: unique(planning_run_id)
SliceDependency: unique(plan_revision_id, predecessor_slice_id,
                        successor_slice_id, kind)
PlanningBundle: unique(bundle_root_sha256)
HumanApproval: at most one active approval per bundle_root_sha256 and actor
```

Immutable digests, source refs, base commits, capability snapshots, cassette
freshness keys, selected candidate identities, and approval bundle roots cannot
be updated in place. Corrections create superseding records and ledger events.

## 6. Inference, constraints, uncertainty, and inspectable project knowledge

The main human trust problem is not merely “what did the model output?” It is:

- what came directly from the plan;
- what was observed in the repository;
- what was inferred;
- what constraint shaped the result;
- how confident the system is;
- what consequence follows if the inference is wrong.

### 6.1 Field-level provenance: the Inference Ledger

Every meaningful generated value accepts a provenance envelope:

```elixir
%{
  origin: :human_explicit | :human_decision | :repo_observed |
          :agent_inferred | :deterministic_derived | :historical_exemplar,
  source_refs: ["plan.md#REQ-004", "app/routes.py:21-58"],
  confidence: :high | :medium | :low | :not_assessed,
  impact: :low | :medium | :high,
  inference_reason: nil | "Route and schema changes appear inseparable",
  approval_status: :not_required | :pending | :accepted | :rejected
}
```

The Workbench defaults to **inference-first review**:

- high-impact, low-confidence facts first;
- scope additions and reinterpretations before copied facts;
- public interfaces and migration assumptions before internal hints;
- accepted defaults and waivers visibly separated from explicit source intent;
- facts copied directly from authoritative sources collapsed by default.

No hidden assumption survives approval.

**Provenance is assigned deterministically wherever it is decidable; the model
only annotates the residual (R5).** A model that self-reports
`origin: :human_explicit` is making an untrusted claim, and a forged or mistaken
provenance tag is a silent trust failure that violates Law 1. So the _compiler_
— not the authoring agent — stamps provenance whenever a field value is a
verbatim or normalization-equal copy of a resolvable source span
(string/AST/span match against the normalized plan or a cited repo span): those
fields are sealed as `human_explicit` / `repo_observed` with the matched
`source_ref`, with no model say-so. Only fields the compiler **cannot** trace
carry the agent's `agent_inferred` envelope — and those are exactly the fields
routed to inference-first review. This turns the §17.3 invariant ("no approved
field whose inference class cannot be recovered") from an assertion into a
checkable property and shrinks the trusted-model surface to the
genuinely-inferred minority.

### 6.2 Assumption register and decision debt

```text
key
statement
affected_refs[]
impact ∈ low | medium | high
confidence
proposed_default?
resolution ∈ unresolved | accepted_default | human_decision | rejected | superseded
introduced_in_revision
review_by_revision?
```

Policy examples:

- any unresolved high-impact assumption blocks approval;
- a public-interface, security, privacy, data-loss, or migration assumption
  always requires explicit acceptance;
- accepted defaults become HumanDecision records at approval;
- an aging accepted default may become decision debt and block a later autonomy
  increase;
- replacing an assumption with repository evidence or a human decision clears
  the debt without rewriting history.

### 6.3 Constraint-aware planning

Plans often fail not because the desired behavior is unclear, but because
implicit real-world constraints were never compiled. Conveyor models them
explicitly.

Examples:

```yaml
constraints:
  - key: CON-001
    kind: migration
    strength: hard
    statement: No destructive database migration in this tranche.
    violation_policy: block
  - key: CON-002
    kind: delivery
    strength: soft
    statement:
      Prefer a plan executable by one engineer-equivalent in three days.
    violation_policy: require_decision
  - key: CON-003
    kind: compatibility
    strength: hard
    statement: Existing API clients must continue to work without modification.
    violation_policy: block
  - key: CON-004
    kind: cost
    strength: soft
    statement: Keep estimated agent spend below the approved budget envelope.
    violation_policy: warn
```

The compiler reports every constraint as:

```text
satisfied
violated
at_risk
not_assessed
not_applicable
```

Hard violations block. Soft violations create a trade-off card showing the
benefit, cost, and alternatives. “The model preferred a different design” is not
a reason to ignore a hard constraint.

### 6.4 Alternative decompositions as a decision surface

For ordinary low-risk plans, one primary decomposition plus the Critic is
sufficient. For high-risk, high-ambiguity, or high-cost plans, policy may
request an independent shadow candidate.

Candidates are compared on deterministic and reviewable dimensions:

```text
requirement coverage
constraint satisfaction
slice independence
atomicity safety
edge count and edge semantics
coordination overhead
shared-oracle density
public-interface churn
approval cognitive load
expected verification burden
novelty / unsupported assumptions
```

Rules:

- candidates never receive final IDs;
- candidates are not automatically blended;
- material disagreement is shown to the human;
- deterministic policy may select only when one candidate strictly dominates on
  hard invariants and neither adds scope;
- otherwise selection is a HumanDecision;
- the unselected candidate remains evidence for later calibration.

### 6.5 Confidence calibration

Agent confidence is not trusted as probability. It is recorded so it can be
calibrated against:

- human edits;
- rejected assumptions;
- downstream contract disputes;
- missing dependencies;
- execution failures attributable to planning;
- critic findings confirmed by real runs.

Until calibration exists, confidence affects review ordering but not authority.
A future learning loop may use empirically calibrated confidence; Phase 2 only
collects the data.

### 6.6 Inspectable ProjectKnowledgeSnapshot

General institutional memory is deferred, but planning still needs project
knowledge. Phase 2 uses an explicit, versioned snapshot built from:

- repository files and manifests;
- `AGENTS.md`;
- ADRs and architecture docs;
- accepted HumanDecisions;
- stable policy;
- optionally, approved high-confidence exemplars from prior successful runs.

Every entry has provenance, expiry/freshness, and removal controls. No invisible
user preference or model-generated summary is injected into planning prompts.

Historical exemplars (“Ghost Context”) are allowed only when:

- the prior run passed all required gates;
- the current archetype and relevant interfaces match;
- the exemplar is clearly labeled as an example, not an instruction;
- sensitive content is excluded or redacted;
- the Workbench shows that an exemplar influenced the plan;
- a held-out evaluation demonstrates that exemplar use improves outcomes without
  copying stale implementation details.

### 6.7 Context representation and semantic compression seam

Planning context may contain:

```text
full_file
bounded_excerpt
symbol_signature
public_types
route_or_schema_snapshot
dependency_edge
quality_finding
historical_exemplar
```

This allows later AST-guided context compression without changing the Context
Pack schema. Phase 2 may use signatures and cited excerpts where reliable, but
must preserve enough source context to avoid misleading agents. Compression is
never allowed to erase provenance or hide uncertainty.

## 7. Phase-2 planning and compiler pipeline

This pipeline begins only after `qualification_gate` passes or an explicit human
override records why limited compiler work may proceed. Every stochastic station
can run live or from a planning-role AgentCassette; deterministic validators are
identical in both modes.

### P2-S1 — Ingest immutable plan revision and ConstraintSet

Inputs:

- source Markdown and `conveyor.plan@1` block/sidecar;
- explicit hard/soft constraints and approved defaults;
- repository identity and base commit;
- human decisions already attached to the Plan;
- current qualification report and capability registry version.

Outputs:

- `PlanRevision`;
- validated `ConstraintSet`;
- normalized plan artifact;
- canonical source-span map;
- `PlanningSpec`, StationPlan, and cassette policy.

Acceptance:

- revision and constraint set are immutable;
- all source references resolve;
- hard constraints have a validation or explicit human-decision path;
- same canonical input produces the same plan and constraint digests;
- qualification status and any override are frozen in PlanningSpec;
- unknown schemas fail explicitly.

### P2-S2 — Deterministic plan audit and interrogation

Extend the Phase-1 PlanAudit with high-precision checks:

- missing or orphan requirements/ACs;
- undefined references;
- unmeasurable acceptance language;
- contradictory enum values, status codes, or interface claims;
- requirements that mix unrelated risk domains;
- missing non-goals;
- missing human decisions for protected architectural choices;
- missing test oracle;
- suspiciously broad “do everything” requirements;
- source plan instructions that conflict with Conveyor policy.

Deterministic findings are authoritative blockers.

### P2-S3 — Agentic Spec Interrogator

A separate, read-only interrogator profile receives:

- normalized plan;
- deterministic findings;
- human decisions;
- policy and question-output schema.

It returns one deduplicated question batch containing:

- ambiguity;
- contradiction;
- untestable requirement;
- hidden dependency;
- missing decision;
- non-goal collision;
- unsafe implied behavior;
- proposed default where appropriate.

The interrogator cannot edit the plan. It asks only.

Rules:

- one batch per revision unless an answer creates a genuinely new conflict;
- hard questions block decomposition;
- soft questions may carry proposed defaults;
- every question states why it matters and what downstream failure it prevents;
- false-alarm feedback is recorded for prompt/eval improvement.

### P2-S4 — Resolve questions into a new revision

Human answers become `HumanDecision` records. Accepting proposed defaults is a
human decision, not silent model authority.

Any answer changing the normalized contract creates a new `PlanRevision` and new
`PlanningSpec`. The prior interrogation remains historical evidence.

### P2-S5 — Planning Context Scout

Before decomposition, build a repository-level planning context artifact. This
is broader than the per-Slice ContextPack.

Contents:

- architecture/module and dependency map;
- public interfaces, schemas, CLI/config surfaces, and ownership hints;
- existing test topology, result adapters, and test commands;
- package/dependency boundaries;
- migrations, persistence model, and data-risk boundaries;
- ADRs, project instructions, and accepted decisions;
- CodeScent or local quality hotspots;
- likely protected paths;
- known conventions and naming patterns;
- dynamic-language uncertainty notes;
- context representations (`full_file`, excerpt, symbol signature, schema,
  dependency edge);
- optional approved historical exemplars with explicit provenance;
- citations and freshness for every observation.

The station is read-only. Start deterministic (`rg`, manifests, route/schema
extractors, language-server/tree-sitter adapters, CodeScent) and allow an
optional read-only planning-scout agent.

An optional `CodeImpactOverlay` maps proposed Slices to modules, symbols, and
interfaces. It is advisory: it visualizes likely blast radius and scope creep,
but does not claim to predict exact edits or block work unless a later mature
extractor is explicitly gate-enabled.

### P2-S6 — Decomposition candidate generation

The Decomposer receives:

- approved normalized PlanRevision and ConstraintSet;
- planning context and optional impact overlay;
- decomposition policy and anti-confetti budget;
- controlled Slice archetype vocabulary;
- required output schema.

It proposes:

- Epics and Slices;
- requirement, decision, and constraint coverage;
- typed dependency edges and atomicity groups;
- likely files, symbols, interfaces, and conflict domains;
- risk and autonomy ceiling;
- structured provided/required interfaces;
- preliminary acceptance criteria;
- non-goals and authorized scope;
- unresolved assumptions;
- `why_this_slice` rationale for every boundary;
- candidate-level trade-offs and known weaknesses.

The primary proposal is an artifact only. For high-risk or high-ambiguity plans,
policy may run a second independent shadow Decomposer. Candidate comparison is
materialized before selection; candidates are never silently blended and do not
create Ash work records.

### P2-S7 — Deterministic work-graph compiler

The compiler:

1. validates candidate schemas and exact PlanningSpec digest;
2. resolves every source, decision, constraint, and interface reference;
3. compares candidates when more than one exists and records selection;
4. assigns canonical stable keys and internal IDs;
5. checks complete requirement, AC, constraint, and non-goal coverage;
6. detects cycles, duplicates, conflicting edges, and unsafe atomicity splits;
7. validates dependency semantics and provider/consumer interface ownership;
8. rejects impossible, orphaned, scope-added, or policy-incompatible Slices;
9. applies size, scope, coordination-overhead, and shared-oracle heuristics;
10. checks hard constraints and reports soft-constraint trade-offs;
11. assigns provenance deterministically for every field that matches a
    resolvable source span, and verifies that each _remaining_ (genuinely
    inferred) field carries a model-supplied `agent_inferred` envelope — no
    field may be both untraceable and unannotated (R5);
12. computes semantic scope delta against human intent;
13. materializes draft Epics, Slices, Agent Briefs, and dependencies in one
    transaction only after all structural checks pass;
14. emits deterministic diagnostics and reusable partial artifacts for repair.

#### Canonical identity policy

Agents never assign final IDs. The compiler assigns stable keys and preserves
identity through explicit `supersedes` relations. Reordering a proposal may not
renumber unrelated Slices.

#### Slice size checks

A Slice is suspicious when it:

- spans multiple unrelated primary behaviors;
- crosses unrelated risk domains;
- has no independently checkable oracle;
- has an unbounded likely-file set;
- requires several unrelated public interface changes;
- cannot produce a complete RunPrompt without placeholders;
- has acceptance criteria that depend on future Epics rather than declared
  dependencies.

These are findings, not simplistic line-count truth. High-risk or ambiguous
cases require split/review.

### P2-S8 — Graph optimization and structural dry-run

Before authoring tests, deterministically inspect and simulate graph
progression:

- topologically traverse the graph and calculate execution waves;
- prove every Slice can eventually become ready;
- distinguish execution, interface, integration, verification, and human edges;
- validate atomicity groups and forbidden intermediate states;
- identify maximum future parallel width without creating a Dispatcher;
- report likely-file, symbol, interface, and conflict-domain collisions;
- report high-fan-out dependencies and single points of failure;
- detect giant Slices, confetti Slices, false parallelism, and shared-oracle
  bottlenecks;
- estimate approval cognitive load;
- compute a structural critical path by edge count/risk;
- show cost/time as `insufficient_history` unless calibrated distributions
  exist.

The optimizer may propose split, merge, or edge-reclassification patches. It
never applies them directly. This is a graph correctness and decision-support
tool, not the future scheduler or economic simulator.

### P2-S9 — Contract Forge

For each Slice, a contract-authoring pass produces a full Agent Brief. The
Decomposer may seed it, but the Contract Forge normalizes it against the actual
contract schema.

Every contract includes:

- current and desired behavior;
- source requirements, decisions, and constraints;
- archetype template and change class;
- structured interfaces, ownership, lock level, compatibility strategy, and
  deprecation policy where applicable;
- acceptance criteria;
- positive, negative, boundary, abuse, and non-goal examples;
- properties/invariants where appropriate;
- required tests, oracle classes, and verification suites;
- authorized scope and protected paths;
- risk and required review lenses;
- likely files and conflict domains as hints, not implementation commands;
- explicit assumptions and challenge cases;
- environment/staging requirements where relevant;
- rollout and rollback intent for high-risk behavior changes;
- done definition and recovery/observability obligations;
- out-of-scope behavior;
- provenance on every inferred field.

#### Interface lock levels

```text
strict               exact public/cross-Slice shape is locked
compatible_superset  additive compatible changes allowed
review_required      changes permitted only through amendment/review
informational        internal implementation hint; not a lock
```

Default to strict only for genuinely public or cross-Slice interfaces.

### P2-S10 — Independent Test Architect

A Test Architect profile distinct from Decomposer, Critic, and implementer
receives:

- normalized plan and Slice contract;
- read-only planning context;
- repository base commit;
- test-author policy;
- write access only to a test-pack workspace.

It produces:

- `TestSpecification` artifact;
- required test IDs and acceptance mappings;
- test roles and explicit oracle definitions;
- at least one falsifying counterexample per machine-checkable AC;
- executable TestPack patch when supported;
- property generators, metamorphic relations, or example tables — **first-class,
  not optional** — for every machine-checkable AC, which must contain or subsume
  the compiler-derived falsifiers defined in P2-S11 (R6);
- hidden challenge cases where policy permits separation from the implementer;
- expected base behavior, expected failure reason, and expected patched
  behavior;
- environment requirements and nondeterminism policy;
- runner commands and result adapters;
- an explicit `human_verification` plan when automation would be dishonest.

#### Test roles

```text
acceptance_new          expected to fail on base for a specific missing behavior
bug_reproduction        expected to fail on base for the reported defect
regression_preservation expected to pass on base and patch
characterization        records current behavior; does not claim correctness
property                checks an invariant over generated cases
interface_contract      verifies a public/cross-Slice interface
security_policy         verifies a policy/security condition
human_verification      explicit manual oracle; blocks higher autonomy
```

This prevents the simplistic assumption that every new locked test must be red
on base.

### P2-S11 — Calibration and test integrity

Hard Phase-2 checks:

1. Test IDs resolve and map to ACs.
2. Baseline-preservation tests pass on base.
3. New-behavior/bug tests fail on base for an expected reason, not import or
   infrastructure breakage.
4. Repeated executions produce a stable result/failure signature.
5. Tests obey sandbox/network/time/RNG policy.
6. The TestPack cannot edit or escape its mount.
7. Required commands and structured result artifacts exist.
8. No test weakens policy or edits production code.
9. Every locked public interface has a declared test oracle, even when dynamic
   coverage cannot yet prove execution.

Integrity status dimensions:

- calibration;
- hermeticity;
- repeatability/flake;
- red-on-stub where a supported honest stub can be generated;
- interface-oracle coverage;
- contract strength assessment.

**Compiler-derived falsifiers (independent of the Test Architect) (R6).** Role
separation is a weak guarantee when every role is the same base model — two
instances share blind spots and will mis-read the same ambiguous AC identically.
The strongest _independent_ oracle is not a second model but a falsifier derived
mechanically from the human-approved AC. The deterministic compiler therefore
emits, for each AC with structured `examples` / `forbidden_behaviors`, at least
one table-driven negative case and (where the AC declares a property/metamorphic
relation) a generated property assertion — anchored to the approved examples,
not to any agent's reasoning. The Test Architect's pack must contain or subsume
these falsifiers; a pack that drops them fails integrity. This gives the P2-S12
"cheapest wrong implementation" critic a floor of genuinely independent tests.

#### What is hard-blocking in Phase 2

Hard-block:

- malformed or missing tests;
- unexpected green on a required red case;
- wrong failure reason;
- flaky or non-hermetic required test;
- vacuous test detected by a supported sentinel;
- missing AC mapping;
- hidden network or secret dependency;
- test-author/implementer role collision.

Advisory until calibrated:

- conventional code mutation score without a legitimate independent reference
  implementation;
- dynamic interface coverage for not-yet-existing code;
- heuristic assertion-strength scores;
- unsupported-language stub analysis;
- model-generated “reference solutions” used only as challenge material.

When a legitimate reference exists, mutation results are one strength dimension,
not the sole readiness score. Surviving mutants are translated into concrete
unverified behaviors. When no reference exists, the Critic's cheapest-wrong-
implementation attack and contract challenge cases carry the burden.

### P2-S12 — Adversarial Contract Critic

A separate critic profile reads only the planning bundle, not hidden generation
reasoning.

Its primary question is:

> “What is the cheapest wrong implementation that could satisfy these written
> acceptance criteria and tests while violating the human’s actual intent?”

Required critic lenses:

- **intent fidelity:** requirement coverage, scope addition/removal, non-goals;
- **principal engineer:** decomposition boundaries, dependency correctness,
  maintainability, atomicity;
- **interface and compatibility:** providers/consumers, versioning, migration;
- **test loophole:** weakest oracle, missing negative/boundary/abuse cases;
- **reliability:** failure modes, observability, rollback, nondeterminism;
- **security and policy:** privilege, secret, data, supply-chain, injection
  risk;
- **cost and simplification:** overdecomposition, unnecessary work, expensive
  verification without value;
- **human-decision audit:** architecture or product judgment hidden as
  inference.

Policy may run these as one structured multi-lens review or separate profiles
for high-risk Slices. Separation from the author is mandatory; model diversity
is measured but not assumed to guarantee independence.

Output is schema-valid findings with stable rule keys, evidence refs, and
concrete proposed repairs. The critic cannot approve or lock contracts.

### P2-S13 — Bounded repair loop

For invalid proposals or critic findings:

- deterministic diagnostics are fed to the responsible authoring role;
- at most two automatic repair rounds per station by default;
- the generator may change only the rejected artifact scope;
- every revision gets a new digest and typed comparison artifact;
- successful upstream artifacts are reused rather than regenerated blindly;
- partial valid Slices remain inspectable even when one candidate fragment
  fails;
- repeated non-progress or oscillation stops and routes to the human;
- material plan or constraint changes cannot be repaired silently; they become
  an amendment or clarification decision;
- a recovery recipe states whether to retry, select an alternative, split,
  weaken nothing, or request human judgment.

### P2-S14 — Prompt dry-compile

Before approval, run the existing PromptBuilder in dry mode for every Slice. A
contract is incomplete if Conveyor cannot render a valid future RunPrompt
without placeholders or unresolved references.

Validate:

- Brief, policy, interfaces, tests, and output schema are present;
- no instruction hierarchy conflict;
- referenced artifacts exist;
- planned autonomy does not exceed adapter/sandbox capability;
- the prompt remains within configured size bounds;
- every untrusted excerpt is labeled.

No implementer is launched.

### P2-S15 — Build canonical approval bundle

The bundle contains:

- qualification status and any explicit override;
- normalized PlanRevision, ConstraintSet, and human decisions;
- question/answer history;
- field-level inference and decision-debt reports;
- every decomposition candidate, comparison, and authoritative selection;
- graph, structural dry-run, anti-confetti findings, and impact overlay;
- requirement/AC/constraint/Slice/interface/test coverage matrices;
- all Agent Briefs, TestSpecifications, challenge cases, and “why this Slice?”
  capsules;
- TestPack calibration, integrity, waivers, and conditional mutation results;
- multi-lens critic findings and repairs;
- risk, compatibility, rollout, recovery, and approval summaries;
- contract and plan diffs from the previous revision;
- unresolved warnings and `not_assessed` capabilities;
- planning prompts, profiles, capability snapshots, policy, cassette provenance,
  and artifact digests;
- a concise Factory Chronicle explaining what Conveyor inferred, changed, and
  still needs from the human.

Approval is impossible until the bundle root digest is stable.

### P2-S16 — Human approval checkpoint

One checkpoint, with Epic-level granularity.

The human can:

- approve or reject an Epic;
- compare and select a decomposition candidate;
- request a Slice split/merge or edge reclassification;
- change an AC, non-goal, constraint, risk, dependency, compatibility strategy,
  rollout intent, or interface lock;
- accept or reject an inferred assumption or waiver;
- mark a Slice as human-verification-only;
- defer a requirement explicitly;
- invoke structured “strengthen contract,” “show cheapest wrong implementation,”
  or “re-run affected stages” actions;
- save a draft decision and resume later without losing the canonical bundle.

Edits never mutate approved truth directly. They create a structured change set,
new PlanRevision where needed, and rerun affected compiler/audit stages.

When all required Epics are approved, `HumanApproval` records:

- approval bundle root digest and selected candidate digest;
- approved Epic/Slice/constraint digests;
- actor and rationale;
- accepted warnings, assumptions, waivers, and decision debt;
- explicit rejected alternatives;
- autonomy ceiling;
- optional signature metadata for a later signing upgrade.

### P2-S17 — Lock and publish ready pool

On approval:

- create final ContractLocks;
- lock TestPacks;
- transition draft Slices to approved;
- mark dependency-free, readiness-clean roots as ready;
- keep blocked descendants approved until dependencies are done;
- project the approved plan bundle;
- emit ledger events and LiveView updates.

A simple deterministic `next_ready` query is allowed. A Dispatcher is not.

### P2-S18 — Sequential execution validation

Select representative approved Slices and run them one at a time through the
existing Phase-1 loop.

This is the compiler’s integration test. Track:

- first-pass gate success;
- implementer clarification/dispute rate;
- context-pack misses;
- missing tests/interfaces;
- contract amendments after execution starts;
- human edits required to make a generated contract runnable.

A Phase-2 release cannot be declared solely from planning artifacts.

### P2-S19 — Compiler scorecard and feedback capture

After each generated Slice reaches a terminal state, attribute outcomes back to
planning artifacts:

- which human edits were needed before approval;
- which assumptions were wrong;
- which critic findings predicted a real failure;
- which dependency or interface edges were missing or unnecessary;
- whether Slice size caused rework or coordination overhead;
- whether context, contract, execution, or gate was the dominant failure class;
- first-pass and eventual success by archetype and planning profile;
- approval time and reversal rate.

This station records learning data only. It does not automatically retrain,
route, or mutate prompts in Phase 2.

---

## 8. Canonical work-graph schema

A new `conveyor.work_graph@1` artifact should be the deterministic intermediate
representation between agent proposals and Ash resources.

```json
{
  "schema_version": "conveyor.work_graph@1",
  "plan_revision_sha256": "...",
  "constraint_set_sha256": "...",
  "selected_candidate_sha256": "...",
  "epics": [],
  "atomicity_groups": [
    {
      "key": "ATOMIC-TASK-SCHEMA-BACKFILL",
      "policy": "same_integration_batch",
      "member_keys": ["SLC-SCHEMA-19A2", "SLC-BACKFILL-32BD"],
      "reason": "Partial integration would expose an unreadable data state"
    }
  ],
  "slices": [
    {
      "stable_key": "SLC-TASK-FILTER-7F3A",
      "title": "Add completed-state filtering",
      "archetype_key": "crud_query_filter",
      "change_class": "behavior_changing",
      "source_refs": ["REQ-014", "AC-021", "CON-003"],
      "constraint_refs": ["CON-003"],
      "why_this_slice": "One independently testable query behavior with one public interface",
      "risk": "low",
      "autonomy_ceiling": "L1",
      "likely_files": ["app/routes.py", "app/repository.py"],
      "likely_symbols": ["list_tasks", "TaskRepository.filter"],
      "conflict_domains": ["tasks_api", "task_query"],
      "provided_interfaces": [],
      "required_interfaces": [],
      "authorized_change_globs": ["app/**", "tests/**"],
      "challenge_case_refs": ["CHAL-021"],
      "rollout_intent": "ordinary",
      "provenance": {}
    }
  ],
  "dependencies": [
    {
      "from": "SLC-SCHEMA-19A2",
      "to": "SLC-TASK-FILTER-7F3A",
      "kind": "interface",
      "interface_keys": ["db.tasks.completed"],
      "rationale": "Filter query requires the persisted completed column",
      "source_refs": ["REQ-014"],
      "provenance": {}
    }
  ],
  "constraint_status": [],
  "scope_delta": "scope_preserved"
}
```

### 8.1 Dependency semantics

Avoid treating every relationship as `blockedBy`.

- `execution_hard`: successor cannot be implemented meaningfully first.
- `interface`: successor depends on an interface; treated as hard in Phase 2,
  later eligible for stub parallelism.
- `integration_order`: implementation may proceed, but merge order matters.
- `verification`: both may execute, but a combined gate waits for both.
  **Consistency note (S1):** a combined/Epic gate is a Phase-4 mechanism (a
  non-goal here, §1.7). In Phase 2, either (a) restrict `verification` edges to
  members of an atomicity group and satisfy them with a minimal "both Slices
  green in one workspace" check in the sequential pilot, or (b) defer the edge
  kind to Phase 4 and ship only `execution_hard` / `interface` /
  `integration_order` / `human_decision` edges. Do not ship an edge type whose
  enforcer does not exist.
- `human_decision`: work blocks on an unresolved decision.
- conflict domains and likely files are **scheduling hints**, never dependency
  edges by themselves.

This distinction prevents needless serialization and preserves the future
throughput path without building it now.

---

## 9. Contract schema upgrades

### 9.1 Structured interfaces

```elixir
%{
  key: "http.patch.tasks.id",
  kind: :http_route | :public_function | :db_table | :db_column | :event |
        :cli_command | :config_key | :internal_boundary,
  direction: :provides | :requires | :modifies,
  display: "PATCH /tasks/{id}",
  stability: :internal | :public | :external,
  lock_level: :strict | :compatible_superset | :review_required | :informational,
  compatibility_policy: :preserve | :additive_only | :versioned_break |
                        :migration_required | :not_applicable,
  deprecation_policy_ref: nil,
  schema_ref: nil,
  owner_path: "app/main.py",
  affected_consumer_refs: [],
  provenance: %{}
}
```

### 9.2 Acceptance criterion

```elixir
%{
  id: "AC-021",
  text: "GET /tasks?completed=true returns only completed tasks",
  kind: :behavioral | :property | :performance | :security | :compatibility |
        :human_judgment,
  requirement_refs: ["REQ-014"],
  interface_refs: ["http.get.tasks"],
  examples: [
    %{kind: :positive, input: %{}, expected: %{}},
    %{kind: :negative, input: %{}, expected: %{}},
    %{kind: :boundary, input: %{}, expected: %{}}
  ],
  forbidden_behaviors: ["must not return incomplete tasks"],
  property_specs: [],
  required_test_refs: [],
  challenge_case_refs: ["CHAL-021"],
  falsifying_counterexample: "A response containing any incomplete task must fail",
  oracle_kind: :automated | :property | :differential | :metamorphic | :human,
  provenance: %{}
}
```

### 9.3 Test specification

```elixir
%{
  test_id: "tests/test_tasks.py::test_filter_completed_true",
  role: :acceptance_new,
  acceptance_refs: ["AC-021"],
  interface_refs: ["http.get.tasks"],
  expected_on_base: :fail,
  expected_base_reason: "completed filter not implemented",
  expected_on_patch: :pass,
  failure_signature_policy: :stable_reason,
  hermeticity_requirements: [:no_network, :fixed_clock, :seeded_rng],
  environment_requirements: [],
  hidden_from_implementer: false,
  result_adapter: "Conveyor.TestResultAdapter.JUnit",
  provenance: %{}
}
```

### 9.4 Contract quality report

Do not reduce readiness to one opaque number. Record dimensions:

```text
traceability
scope_boundedness
interface_clarity
dependency_clarity
acceptance_testability
test_calibration
test_integrity
adversarial_robustness
prompt_compilability
human_judgment_requirements
constraint_satisfaction
scope_fidelity
compatibility_safety
atomicity_safety
approval_cognitive_load
recovery_completeness
```

Each dimension is `pass | warn | fail | not_assessed` with evidence. Scores may
support sorting, but no weighted aggregate can override a failed hard dimension.

### 9.5 Archetype contract templates

Templates are deterministic minimum obligations, not prompt folklore.

| Archetype                 | Mandatory obligations                                                             |
| ------------------------- | --------------------------------------------------------------------------------- |
| `bugfix_regression`       | reproduction, cause hypothesis, regression test, unchanged-behavior list          |
| `crud_endpoint`           | request/response schema, negative status cases, persistence reflection            |
| `pure_refactor`           | behavior oracle, public-interface freeze, allowed divergences                     |
| `schema_migration`        | forward compatibility, data validation, reversibility class, backup/rollback plan |
| `dependency_update`       | rationale, lockfile scope, compatibility/security checks, rollback                |
| `public_interface_change` | consumer impact, compatibility policy, version/deprecation strategy               |
| `security_hardening`      | threat/abuse case, negative tests, mandatory security lens                        |
| `performance`             | workload, baseline, threshold, variance and regression budget                     |
| `configuration`           | default, precedence, invalid values, secret handling                              |

A `custom` archetype is permitted but receives higher review scrutiny.

### 9.6 Rollout and environment intent

A contract may declare future verification/release needs without granting
deployment authority:

```text
rollout_kind ∈ ordinary | feature_flag | dark_launch | migration_window | manual
rollback_expectation
staging_environment_required
fault_injection_profile?
traffic_or_data_safety_notes[]
```

Phase 2 records these as intent and uses them to shape tests. Ephemeral staging,
dark launches, and production rollout remain later-phase mechanisms.

### 9.7 Migration safety profile

For migration archetypes, the contract must classify:

```text
reversibility ∈ reversible | compensating | irreversible
backfill_strategy
data_validation_queries[]
compatibility_window
rollback_or_restore_plan
performance_risk
```

A future migration sandbox may apply changes to a disposable database clone and
verify semantic restoration. Exact byte-for-byte restoration is not assumed to
be generally meaningful; validation is defined by declared data and behavior
invariants.

---

## 10. Qualification Cockpit and Human Approval Workbench

Operator clarity is a control mechanism. The UI must help the human make the
right decision with less cognitive effort, not merely expose more data.

### 10.1 Two related surfaces

#### Qualification Cockpit

Shows whether the existing execution loop is safe to amplify:

- active Battery corpus and holdout coverage;
- primary and secondary adapter capability snapshots;
- live, hybrid, and full-replay coverage clearly distinguished;
- gate canary and trust-tool meta-canary health;
- TestPack integrity and waivers;
- cassette freshness and replay divergence;
- top failure classes and triage confusion matrix;
- cost, duration, first-pass, eventual success, rework, and context misses;
- open `PhaseNextDecision` branches and the evidence needed to close them.

#### Plan Workbench

Shows what Conveyor believes the human plan means and what will execute:

1. **Intent view** — goal, non-goals, decisions, unresolved assumptions.
2. **Constraint view** — hard/soft constraints, satisfaction, trade-offs.
3. **Candidate view** — alternate decompositions, material disagreements, and
   selected rationale.
4. **Traceability matrix** — requirements → ACs → constraints → Slices → tests.
5. **Graph view** — Epics, Slices, typed dependencies, atomicity groups,
   structural waves.
6. **Code-impact view** — likely modules/symbols/interfaces and extractor
   confidence.
7. **Inference view** — everything inferred, copied, observed, or derived.
8. **Contract view** — Brief, interface locks, compatibility, challenge cases,
   scope, tests, rollout intent.
9. **Risk and recovery view** — high-risk Slices, protected paths, required
   reviews, possible failure paths, rollback/repair options.
10. **Quality view** — audit, calibration, integrity, waivers, critic findings.
11. **Diff view** — current revision/bundle vs prior revision/approval.
12. **Approval view** — Epic-level decisions, accepted warnings, autonomy cap.

### 10.2 Progressive disclosure and review ordering

Default ordering:

1. blockers and hard-constraint violations;
2. scope additions/removals/reinterpretations;
3. high-impact assumptions and waivers;
4. public interfaces, migrations, security/privacy/data risks;
5. candidate disagreements;
6. low-confidence dependencies and oracles;
7. critic loopholes and challenge cases;
8. ordinary copied facts.

The operator can drill to raw artifacts, but the default is a concise decision
surface. Unchanged or directly copied content is collapsed.

### 10.3 Structured actions, not freeform hidden mutation

The human can invoke:

```text
approve_epic
reject_epic
select_candidate
accept_or_reject_assumption
accept_or_reject_waiver
split_slice
merge_slices
reclassify_dependency
strengthen_contract
show_cheapest_wrong_implementation
change_constraint
change_interface_lock
change_compatibility_strategy
mark_human_verification
rerun_affected_stages
open_amendment
save_draft_and_resume
```

Every action produces a typed change set. Actions that change intent,
constraints, acceptance, scope, or interfaces create a new PlanRevision or
amendment and rerun only invalidated stages. No form field edits canonical rows
in place.

### 10.4 Candidate comparison as a first-class decision surface

For each candidate, show:

- what it optimizes;
- requirement and constraint coverage;
- Slice count and anti-confetti warnings;
- critical path and structural parallelism;
- public-interface churn;
- atomicity and migration risk;
- expected verification burden;
- inferred assumptions;
- approval load;
- critic objections.

The Workbench supports side-by-side comparison and a typed “selected because”
statement. It does not synthesize a third candidate behind the human's back.

### 10.5 Recovery-first UX

Every blocked or failed station displays:

- what completed successfully;
- what failed and the confidence in that classification;
- what artifacts can be reused;
- whether a retry uses the same spec;
- whether a new decision, lock, or revision is required;
- the safest next actions;
- expected blast radius of each action;
- links to typed evidence differences.

A user returning later sees the same canonical state and can resume from the
last durable checkpoint.

### 10.6 “Strengthen this contract” action

This is a structured orchestration, not a magic button. It may:

1. rerun the Test Architect on named weak dimensions;
2. ask the Critic for the cheapest wrong implementation;
3. generate additional negative/boundary/challenge cases;
4. rerun supported integrity checks;
5. compare old and new contract quality;
6. require approval for any acceptance or scope change.

The action never silently broadens scope or lowers a threshold.

### 10.7 Factory Chronicle and explainability

`approval_summary.md` remains the authoritative static summary. An optional
`factory_chronicle.md` provides a narrative:

- what the human asked for;
- what Conveyor inferred;
- how the plan was decomposed and why;
- which alternatives were rejected;
- what contracts and tests protect the intent;
- what remains uncertain or human-verified;
- what changed since the previous revision;
- what the next operational step is.

This is generated from canonical artifacts, clearly labeled as a summary, and
never substitutes for evidence. The same mechanism can later support operator
education and a “Conveyor Academy” experience without adding authority.

**Fidelity is not quality (S3).** The `approval_summary.md` and Factory
Chronicle must carry an explicit "What Conveyor did NOT evaluate" banner:
Conveyor verifies that the _compilation faithfully represents the human's plan_
(scope fidelity, provenance, traceability, adversarial contract robustness). It
does **not** evaluate whether the plan is the right thing to build. A flawless
green bundle for a faithfully-compiled bad plan looks exactly as trustworthy as
one for a good plan; the operator must not read process rigor as product
correctness. This one sentence is the cheapest guard against the most expensive
failure mode of a very convincing compiler.

### 10.8 Static and headless parity

Everything required for approval or recovery is available through:

- machine JSON;
- static Markdown reports;
- Mix tasks;
- LiveView.

A headless operator must not receive a weaker trust experience. LiveView may add
interaction and visualization, but it cannot hide a blocker, invent a status, or
become the only way to approve.

### 10.9 Explicitly deferred interaction complexity

Do not build in this program:

- arbitrary drag-and-drop graph mutation;
- collaborative cursors, comments, or live co-editing;
- natural-language chat that mutates contracts without a typed change set;
- a general project-management board;
- auto-approval prediction;
- premium-only forks of the architecture.

The Workbench should feel powerful because it is legible, fast, and safe—not
because it reproduces every IDE and project-management interaction.

### 10.10 Human-centered evals

Measure:

- time to identify the highest-risk inferred fact;
- time to explain why one candidate was selected;
- approval reversal rate after execution starts;
- percentage of failures diagnosed without database access;
- task success on “find what changed” and “what can I safely retry?” exercises;
- approval cognitive load and operator confidence;
- whether narrative summaries improve understanding without hiding evidence.

These metrics complement, but never replace, correctness gates.

## 11. Plan amendments, contract disputes, and staged micro-negotiation

Immutable contracts must be strict without becoming brittle. The sanctioned
escape valve is explicit contract evolution, never hidden drift.

### 11.1 Material amendment path

A material proposal:

1. records evidence, affected refs, constraints, interfaces, and originating
   attempt;
2. terminates any in-flight immutable attempt cleanly;
3. moves the affected Slice to `contract_disputed` or keeps it unready;
4. computes affected, downstream, and potentially invalidated artifacts;
5. creates a proposed redline against the normalized plan/contract;
6. requires a HumanDecision;
7. creates a new PlanRevision and PlanningSpec when accepted;
8. recompiles and re-audits only the affected subgraph plus required dependents;
9. creates new ContractLocks, RunSpecs, and future RunAttempts;
10. leaves historical evidence interpretable against old locks.

Material includes any change that:

- weakens/removes an AC;
- adds/removes scope or a requirement;
- changes a human decision or hard constraint;
- narrows a safety, compatibility, or policy obligation;
- alters a public/cross-Slice interface incompatibly;
- changes an irreversible migration or data-loss posture;
- increases the granted autonomy.

### 11.2 Micro-negotiation modes

The system records structured low-stakes friction from the start, but automation
is staged.

#### Mode 1 — `human_gated` (default Phase-2 authority)

The implementer or planning role proposes a precise delta. The deterministic
materiality classifier and contract-author reviewer produce a recommendation;
the human accepts or rejects it. This establishes a labeled corpus.

#### Mode 2 — `shadow_adjudication`

Conveyor records what it **would** have auto-accepted under a narrow policy, but
still requires the human. Compare shadow decisions with human outcomes and
post-execution evidence.

#### Mode 3 — `pre_attempt_auto_accept` (conditional, not required for release)

May be enabled only after a project-specific evidence threshold and zero known
weakening escapes. Eligible changes are limited to strict compatibility
supersets, examples, or type clarifications that:

- do not touch AC text, decisions, hard constraints, scope, policy, or risk;
- preserve all existing callers;
- are confirmed by a distinct contract-author actor;
- occur before a new execution attempt begins;
- create a new ContractLock, RunSpec, and RunAttempt;
- remain bounded by a negotiation-round limit.

No mode may modify an active attempt in place.

### 11.3 Negotiation record

```text
request_kind
originating_role
originating_attempt_id?
proposed_delta_ref
materiality
materiality_reason
affected_refs[]
contract_author_verdict
shadow_or_actual_adjudication
human_decision_id?
resulting_plan_revision_id?
resulting_contract_lock_id?
resulting_run_attempt_id?
round_index
```

Rejected or abusive disputes are recorded for later routing/trust analysis, but
Phase 2 does not mechanize agent reputation.

### 11.4 No retry penalty for contract faults

When execution discovers an impossible or materially wrong contract:

- classify it as a plan/contract fault, not an implementation failure;
- do not consume the implementer's rework or escalation budget;
- terminate the immutable attempt cleanly;
- preserve its evidence and partial patch as non-authoritative diagnostic input;
- route through amendment;
- start a new attempt only after a new lock is approved.

### 11.5 Selective invalidation

The amendment compiler computes invalidation by semantic dependency, not broad
timestamps.

Possible outcomes:

```text
unchanged_digest_reusable
revalidate_only
regenerate_contract
regenerate_test_pack
recompile_prompt
reapprove_epic
invalidate_downstream_attempt
```

An unaffected Slice retains its digest and approval only when all referenced
intent, constraints, interfaces, tests, and dependencies remain semantically
unchanged.

### 11.6 Amendment abuse and safety evals

Fixtures must prove:

- a genuine impossible contract routes to amendment without retry penalty;
- an agent cannot label acceptance weakening as “clarification”;
- an interface superset is not treated as safe when it changes semantics;
- selective invalidation preserves genuinely unaffected contracts;
- an amendment that changes a shared interface invalidates all consumers;
- round limits prevent negotiation loops;
- shadow adjudication never gains authority accidentally.

## 12. Evidence Time Machine, triage, and recovery kernel

The program builds the **kernel** of these capabilities now because both
qualification and compiler development depend on them. Rich visual forensics and
fully autonomous repair remain later.

### 12.1 Typed comparison engine

The comparator normalizes and compares:

- BatteryCase, BatteryRun, and expected outcome;
- Agent capability snapshot and cassette freshness;
- PlanRevision and ConstraintSet;
- PlanningSpec / RunSpec;
- decomposition candidate and selected graph;
- ContractLock, Brief, TestPack, Policy, DiffPolicy;
- prompt/template/context and ProjectKnowledgeSnapshot;
- PatchSet and authorized scope;
- gate stages, canary suite, and environment image;
- artifact manifest and digest chain;
- reviewer/critic dossier inputs and outputs;
- HumanApproval and amendment lineage.

Materiality classification:

```text
identical
cosmetic
context_only
evidence_changing
scope_added
scope_removed
scope_reinterpreted
contract_changing
acceptance_weakened
acceptance_strengthened
policy_weakened
policy_strengthened
environment_changing
capability_changing
incomparable
```

Comparison fails closed on a missing, redacted-without-authority, or digest-
mismatched blob. It respects sensitivity metadata and never renders quarantined
raw content by default.

### 12.2 Core commands

```bash
mix conveyor.diff_runs RUN_A RUN_B [--section contract|gate|patch|spec|context]
mix conveyor.diff_plans REV_A REV_B
mix conveyor.diff_candidates CANDIDATE_A CANDIDATE_B
mix conveyor.diff_artifacts ARTIFACT_A ARTIFACT_B
mix conveyor.why_stale SUBJECT_ID
mix conveyor.why_different LEFT RIGHT
```

Every command can emit canonical JSON and Markdown.

### 12.3 Deterministic-first triage

Rules consume structured station errors, gate stages, integrity verdicts,
findings, budgets, context usage, and freshness state before consulting any
agent.

Core classifications and default recipes:

```text
brief_failure          → revise/split contract before execution
ambiguous_plan         → consolidated question batch
contradictory_plan     → hard clarification
invalid_graph          → repair candidate with compiler diagnostics
oversized_slice        → split proposal
confetti_graph         → coalescing/edge review
missing_interface      → Contract Forge repair
weak_oracle            → Test Architect repair or human verification
invalid_test_pack      → Test Architect repair
context_miss           → regenerate ContextPack; same contract, new attempt
implementation_bug     → retry/rework under same contract
validation_failure     → fix implementation; same contract unless evidence says otherwise
impossible_contract    → amendment; no implementation retry penalty
flaky_required_test    → repair/replace/waive; cannot silently pass
infra_failure          → reconcile, doctor, and idempotent station retry
policy_violation       → stop, incident, human/policy repair
budget_exhausted       → park or authorized escalation
reviewer_unhealthy     → recalibrate reviewer; no acceptance
cassette_stale         → live run or explicit no-cassette failure
gate_false_negative    → stop the line; repair gate and rerun corpus
unknown                → human escalation with preserved partial artifacts
```

### 12.4 Advisory triage reviewer

An optional distinct profile may analyze the dossier only when deterministic
rules return `unknown` or multiple plausible classes. Its output includes
confidence and competing hypotheses. It may recommend, but cannot auto-apply:

- contract or acceptance changes;
- policy changes;
- scope changes;
- human waivers;
- autonomy changes.

### 12.5 Recovery recipe schema

```json
{
  "schema_version": "conveyor.rework_recipe@1",
  "classification": "context_miss",
  "confidence": "high",
  "evidence_refs": ["..."],
  "reusable_artifact_refs": ["contract_lock:...", "test_pack:..."],
  "invalidated_artifact_refs": ["context_pack:...", "run_prompt:..."],
  "recommended_action": "retry_same_contract_with_new_context",
  "requires_new_spec": true,
  "requires_human": false,
  "idempotent": true,
  "commands": ["mix conveyor.retry RUN_ID --refresh-context"]
}
```

### 12.6 Safe auto-actions

Only actions with deterministic preconditions, idempotency, and bounded budgets
may auto-apply in this program:

- reconcile an unknown external effect;
- rerun a failed infrastructure station;
- regenerate a stale artifact projection;
- rerun a stale canary;
- regenerate ContextPack and create a new attempt under the same contract;
- replay a matching cassette.

Everything affecting intent, scope, acceptance, policy, interface compatibility,
waivers, or approval remains human-gated.

### 12.7 Triage honesty eval

The Battery and injected station failures provide known labels. Report a
confusion matrix, per-class precision/recall, and coverage. The ambiguity trap
must remain `unknown`; fabricated high confidence is a release-blocking bug.

### 12.8 Chronicle and smart continuation

At terminal states, Conveyor emits a small set of high-signal next actions, for
example:

- inspect material diff;
- retry same contract with refreshed context;
- strengthen the oracle;
- split the Slice;
- open an amendment;
- compare candidate alternatives;
- approve the ready Epic;
- execute the next dependency-ready Slice.

These are deterministic projections over state and recipes, not engagement
prompts. They make the system feel continuous without creating hidden background
work.

## 13. OTP / Oban topology

Reuse the existing Phase-0/1 conductor, StationRun, StationEffect, outbox,
reconciler, and sandbox model. Add durable jobs; do not create a second
orchestrator framework.

```text
Conveyor.Conductor.Supervisor
├── existing Phase-0/1 services
├── Conveyor.Qualification
│   ├── Corpus
│   ├── Gate
│   └── Report
├── Conveyor.Cassettes
│   ├── Recorder
│   └── Resolver
├── Conveyor.Evidence.Comparator
├── Conveyor.Triage.Engine
├── Conveyor.Planning.Compiler
├── Conveyor.Planning.Identity
├── Conveyor.Planning.ConstraintCompiler
├── Conveyor.Planning.CandidateComparator
├── Conveyor.Planning.Approval
└── Oban workers
    ├── Phase 1.5
    │   ├── Conveyor.Jobs.RunBattery
    │   ├── Conveyor.Jobs.RecordAgentCassette
    │   ├── Conveyor.Jobs.VerifyCassetteReplay
    │   ├── Conveyor.Jobs.AssessTestIntegrity
    │   ├── Conveyor.Jobs.RunTrustMetaCanaries
    │   ├── Conveyor.Jobs.BuildEvidenceComparison
    │   ├── Conveyor.Jobs.TriageFailure
    │   ├── Conveyor.Jobs.RunScopedBehaviorLock
    │   ├── Conveyor.Jobs.RunQualificationStudies
    │   └── Conveyor.Jobs.RunQualificationGate
    └── Phase 2
        ├── Conveyor.Jobs.StartPlanningRun
        ├── Conveyor.Jobs.InterrogatePlan
        ├── Conveyor.Jobs.BuildPlanningContext
        ├── Conveyor.Jobs.GenerateDecompositionCandidate
        ├── Conveyor.Jobs.CompareDecompositionCandidates
        ├── Conveyor.Jobs.CompileWorkGraph
        ├── Conveyor.Jobs.OptimizeWorkGraph
        ├── Conveyor.Jobs.ForgeContracts
        ├── Conveyor.Jobs.AuthorTestPacks
        ├── Conveyor.Jobs.CalibrateTestPacks
        ├── Conveyor.Jobs.AssessPlanningTestIntegrity
        ├── Conveyor.Jobs.ReviewContracts
        ├── Conveyor.Jobs.RepairPlanningArtifact
        ├── Conveyor.Jobs.DryCompilePrompts
        ├── Conveyor.Jobs.ProjectPlanningBundle
        ├── Conveyor.Jobs.ApplyPlanApproval
        ├── Conveyor.Jobs.ApplyPlanAmendment
        ├── Conveyor.Jobs.ScoreCompilerOutcome
        └── Conveyor.Jobs.RunPhase2Gate
```

### 13.1 Station identity and idempotency

Qualification station key:

```text
battery_run_id + battery_case_id + station_key + station_spec_sha256 + attempt_no
```

Planning station key:

```text
planning_run_id + station_key + station_spec_sha256 + attempt_no
```

Cassette identity:

```text
spec_kind + spec_sha256 + role + adapter + agent_profile_snapshot_sha256
```

A retry first reconciles any unknown external effect. Cassette resolution is a
read effect; live provider calls, sandbox starts, process execution, and
artifact projection remain declared StationEffects.

### 13.2 Agent adapters

Adapters behind `AgentRunner`:

```text
AgentRunner.PrimaryLive
AgentRunner.SecondaryLive
AgentRunner.Replay
AgentRunner.MockDegraded   # deterministic capability-mismatch conformance gate (R7)
```

The plan does not hardcode a vendor into the core. The secondary adapter is
chosen at implementation time based on current headless operation, event
streaming, policy interception, cancellation, diff capture, and licensing. A
vendor-specific hook is capability evidence, not a permanent architecture law.

Planning roles use the same adapter interface with role-specific output schemas:

```text
interrogator
planning_scout
decomposer
contract_author
test_architect
contract_critic
triage_reviewer
```

### 13.3 Planning role policy matrix

| Role            | Repo access                 | Source writes | Test-pack writes        | Authority           |
| --------------- | --------------------------- | ------------- | ----------------------- | ------------------- |
| Interrogator    | plan only / bounded context | no            | no                      | asks questions      |
| Planning Scout  | read-only                   | no            | no                      | context proposal    |
| Decomposer      | read-only planning context  | no            | no                      | candidate proposal  |
| Contract Author | read-only                   | no            | no                      | contract proposal   |
| Test Architect  | read-only source            | no            | isolated test workspace | test proposal       |
| Contract Critic | planning bundle read-only   | no            | no                      | findings only       |
| Triage reviewer | dossier read-only           | no            | no                      | advisory hypothesis |

No role can approve, lock, alter policy, or directly materialize canonical work.

### 13.4 Optional Tutor process

If the measured Tutor experiment is enabled, it runs inside the implementation
container for latency and writes advisory iterations through the existing event
channel. It is not a second authoritative gate or a long-lived global process.

### 13.5 Telemetry additions

Add bounded spans/metrics for:

```text
conveyor.battery.case
conveyor.cassette.record
conveyor.cassette.replay
conveyor.station.test_integrity
conveyor.evidence.compare
conveyor.triage
conveyor.planning.interrogate
conveyor.planning.decompose
conveyor.planning.compile
conveyor.planning.contract_forge
conveyor.planning.test_architect
conveyor.planning.critic
conveyor.planning.approval
```

Allowed dimensions remain bounded: archetype, adapter, role, station, status,
failure class, run mode, risk, and review lens. Raw paths, prompts, errors, and
model prose remain artifacts rather than metric labels.

### 13.6 Planning-stage memoization

A content-addressed planning-stage cache keyed on each stage's input digest
(S4). During iterative authoring — human edits the plan, recompiles against the
same repo base commit — unchanged upstream stages (e.g. the Planning Context
Scout, keyed on repo base commit + scout profile) return cached artifacts
instead of re-running expensive repo analysis or agent calls. Everything is
already content-addressed, so this is a lookup, not new machinery; it makes the
width-one pipeline tolerable to iterate on. A cache hit is a read effect, never
an authority shortcut: deterministic validators still re-run on the reused
artifact's digest.

## 14. Operator interface

Keep Mix tasks close to a future standalone CLI. Commands emit concise human
output plus canonical JSON when requested.

### 14.1 Phase-1.5 commands

```bash
mix conveyor.phase_next_decision
mix conveyor.battery [--case ID | --archetype KEY] [--adapter PROFILE]
                     [--mode live|replay_full|replay_hybrid]
mix conveyor.battery_report BATTERY_RUN_ID
mix conveyor.qualification_gate PROJECT_ID
mix conveyor.record_cassette RUN_ATTEMPT_ID
mix conveyor.replay RUN_ATTEMPT_ID --mode replay_full|replay_hybrid
mix conveyor.test_integrity SLICE_ID
mix conveyor.trust_canaries PROJECT_ID
mix conveyor.diff_runs RUN_A RUN_B [--section SECTION]
mix conveyor.why_stale SUBJECT_ID
mix conveyor.triage SUBJECT_ID
mix conveyor.qualification_study PROJECT_ID --vary scout|agents_md|prompt|adapter|tutor
mix conveyor.publish_pr RUN_ATTEMPT_ID --disposable-repo   # conditional
```

### 14.2 Phase-2 commands

```bash
mix conveyor.plan_revision PLAN.md [--constraints constraints.yml]
mix conveyor.plan_interrogate PLAN_REVISION_ID
mix conveyor.plan_answer PLAN_REVISION_ID answers.yml
mix conveyor.plan_prepare PLAN_REVISION_ID
mix conveyor.plan_candidates PLAN_REVISION_ID
mix conveyor.plan_compare_candidates CANDIDATE_A CANDIDATE_B
mix conveyor.plan_select_candidate PLANNING_RUN_ID CANDIDATE_KEY
mix conveyor.plan_graph PLAN_REVISION_ID
mix conveyor.contract_audit SLICE_ID
mix conveyor.contract_strengthen SLICE_ID --dimension test_loophole
mix conveyor.plan_bundle PLAN_REVISION_ID
mix conveyor.plan_diff OLD_REVISION NEW_REVISION
mix conveyor.plan_approve PLAN_REVISION_ID approval.yml
mix conveyor.plan_amend PLAN_REVISION_ID amendment.yml
mix conveyor.next_ready PLAN_ID
mix conveyor.factory_chronicle PLAN_REVISION_ID
mix conveyor.phase2_demo
mix conveyor.phase2_gate PROJECT_ID
```

`mix conveyor.plan_prepare` runs through approval-ready and stops. It never
self-approves or launches an implementer.

### 14.3 Stable exit codes

```text
0   action successful / gate passed
1   deterministic execution gate failed
2   clarification or readiness block
3   policy, secret, or trust-boundary violation
4   infrastructure/doctor/reconciliation failure
5   adapter or provider failure
6   canary, meta-canary, or eval false verdict
7   malformed artifact, digest, or schema failure
8   decomposition/candidate/graph compile failure
9   contract/test integrity failure
10  human approval required or rejected
11  amendment / contract dispute required
12  cassette missing or stale in replay-only mode
13  qualification gate not satisfied
14  phase2 gate not satisfied
```

### 14.4 LiveView surfaces

- **Qualification Cockpit** — Battery, adapters, canaries, integrity, replay,
  branches, and gate status.
- **Plan Workbench** — intent, constraints, candidates, graph, inference,
  contracts, quality, diffs, approval.
- **Evidence Time Machine** — typed comparisons and stale explanations.
- **Recovery Queue** — triaged failures, reusable artifacts, safe next actions.
- **Contract Quality Dashboard** — calibration, integrity, challenge cases,
  waivers, conditional mutation results.
- **Factory Chronicle** — narrative projection linked to raw evidence.

### 14.5 Permission modes

The UI should make authority visible using three product modes over the same
policy substrate:

```text
inspect   read-only projections and comparisons
suggest   generate typed changes requiring human approval
execute   perform only pre-approved, policy-bounded actions
```

These modes are product affordances, not new autonomy levels. Actual authority
still derives from Policy, capability snapshots, approvals, and the autonomy
ceiling.

## 15. Safety and threat-model additions

### 15.1 Phase-1.5 threats

- a live adapter bypasses pre-execution policy through its native tool loop;
- adapter capability drift leaves old autonomy assumptions in place;
- a Cassette is replayed after contract, policy, image, prompt, or capability
  changes;
- full replay is misrepresented as proof of current gate freshness;
- a Battery known-good solution leaks to the implementer;
- trap metadata reveals the expected defense;
- a flaky required test is quarantined and the run is incorrectly marked green;
- a triage model fabricates confidence and auto-applies a harmful action;
- sensitive live-run output is promoted into a reusable cassette;
- Battery overfitting improves fixtures while degrading real work.

Defenses:

- capability snapshots in every RunSpec;
- autonomy derived from capabilities, not adapter names;
- exact cassette freshness keys and explicit replay trust levels;
- hidden-oracle mount separation and artifact sensitivity policies;
- required-test waiver rules;
- deterministic triage before advisory review;
- meta-canaries and held-out/rotating Battery cases;
- redaction/quarantine before cassette sealing.

### 15.2 Phase-2 threats

- plan text instructs planning roles to bypass policy;
- repository docs/comments poison decomposition or Test Architect output;
- Decomposer invents requirements or silently removes difficult scope;
- a soft constraint is treated as absent or a hard constraint as negotiable;
- candidate comparison hides a material disagreement;
- Test Architect encodes narrower behavior than the AC;
- generator and critic collude through shared hidden context;
- historical exemplars cause stale implementation copying;
- impact overlays are mistaken for exact code knowledge;
- human approves a bundle different from the one later locked;
- repair loops silently weaken acceptance or compatibility;
- generated IDs collide or drift across revisions;
- test-author workspace mutates production source;
- an amendment invalidates downstream contracts without detection;
- a compatibility bridge proposal hides a breaking change;
- a narrative summary omits a blocker that exists in canonical evidence.

Defenses:

- explicit trust labels on plan, repository, tool, and exemplar excerpts;
- prompt-injection fixtures for every role;
- field-level provenance and semantic scope-delta checks;
- hard/soft ConstraintSet validation;
- independent candidate artifacts and recorded selection;
- separate profiles, actor policies, and role-specific write roots;
- bundle-root approval binding and projection parity tests;
- contract-diff classification with weakening blocked;
- deterministic identity assignment and supersession;
- bounded repair loops and typed invalidation;
- read-only production mounts for Test Architect;
- compatibility and consumer-impact checks;
- summary completeness canary against raw bundle blockers.

### 15.3 Secret and sensitivity handling

Battery fixtures, cassettes, planning context, and chronicles inherit Phase-1
Artifact sensitivity. Additional rules:

- never seal raw provider credentials or environment secrets into a cassette;
- redact before creating reusable exemplars;
- hidden oracle and known-good solution refs are `sensitive` and unavailable to
  implementation roles;
- comparison commands require authority for both subjects;
- static reports omit quarantined raw blobs but preserve their existence and
  digest;
- no future memory/index may ingest sensitive artifacts without explicit policy.

### 15.4 Supply-chain and adapter drift

Adapter and tool versions are part of spec freshness. A capability probe runs
before live qualification. Any material change to adapter behavior, sandbox
image, result parser, mutation/integrity adapter, or code-impact extractor:

- invalidates relevant cassettes and health summaries;
- requires conformance replay;
- may lower autonomy until requalified;
- is visible in EvidenceComparison;
- expires or downgrades every QualificationGrant whose `invalidation_triggers`
  match, so authority cannot outlive the evidence that earned it (R3).

### 15.5 Safety invariants

- no agent role can approve its own output;
- no cassette can create authority absent a fresh deterministic check;
- no required acceptance signal disappears without a HumanDecision;
- no plan/constraint/contract weakening is auto-applied;
- no summary can claim green when a canonical blocker exists;
- no planning artifact can directly execute shell commands;
- no future staging, chaos, migration, or rollout hook is active in this program
  unless explicitly listed as a built station.

## 16. Evaluation, canary, replay, and human-legibility strategy

### 16.1 Layered test strategy

| Layer                           | Purpose                                             | Default execution                   |
| ------------------------------- | --------------------------------------------------- | ----------------------------------- |
| Unit/property tests             | deterministic compiler, schemas, identity, policies | every CI run                        |
| Fixture integration             | station orchestration with fake outputs             | every CI run                        |
| Cassette full replay            | high-fidelity conductor/artifact regression         | every CI run where cassette exists  |
| Cassette hybrid replay          | live gate against recorded stochastic output        | nightly/pre-release                 |
| Live Battery                    | real adapter outcome sampling                       | qualification and scheduled refresh |
| Gate canaries                   | known-bad patches must fail                         | gate freshness / release            |
| Trust meta-canaries             | trust tools must catch labeled defects honestly     | release                             |
| Planning proposal replay        | recorded proposal through current compiler          | every Phase-2 CI run                |
| Live planning eval              | current models on frozen PlanningSpecs              | tagged/manual/scheduled             |
| Downstream generated-Slice eval | compiler outputs survive real execution             | Phase-2 release                     |
| Human legibility eval           | operator can understand, approve, and recover       | milestone/release study             |

### 16.2 Deterministic CI suites

```text
phase_next_decision
battery_corpus_validation
battery_runner
cassette_freshness
cassette_full_replay
adapter_conformance
integrity_sentinel
trust_meta_canaries
evidence_comparison
triage_rules
plan_revisioning
constraint_compiler
interrogation
candidate_comparison
work_graph_compiler
stable_identity
dependency_semantics
atomicity_groups
anti_confetti
traceability
scope_delta
contract_audit
test_pack_calibration
test_integrity
critic_schema
review_lenses
repair_loop
approval_digest
plan_amendment
selective_invalidation
prompt_dry_compile
planning_bundle_replay
planning_prompt_injection
chronicle_completeness
```

### 16.3 Battery and holdout policy

- the core Battery is versioned and content-addressed;
- at least one rotating held-out group is excluded from ordinary prompt tuning;
- every new failure class should become a fixture, mutant, or meta-canary when
  an honest oracle exists;
- changing expected outcomes requires review and a corpus version bump;
- live runs sample nondeterminism; cassette runs test deterministic regressions;
- no single provider outage should invalidate historical qualification, but a
  stale capability snapshot may require requalification before new authority.

### 16.4 Meta-canary matrix

Minimum release-blocking cases:

```text
vacuous_test_caught
clean_test_not_quarantined
required_flake_blocks_green
contract_weakening_material
cosmetic_diff_not_material
ambiguous_triage_returns_unknown
stale_cassette_rejected
matching_cassette_replayed
bundle_byte_change_invalidates_approval
prompt_injection_ignored
benign_repo_text_not_blocked
interrogator_completeness_under_injection   # malicious plan/repo cannot suppress a required question (S5)
silent_refactor_drift_detected
allowed_normalized_variance_passes
scope_added_requires_approval
hard_constraint_violation_blocks
summary_cannot_hide_blocker
```

### 16.5 Labeled planning eval corpus

Create fixtures containing:

- clean multi-Epic plan;
- missing requirement and constraint coverage;
- contradictory status codes/interfaces;
- untestable quality language;
- hidden architecture decision;
- intentionally oversized Slice;
- confetti decomposition with excessive fixed overhead;
- unsafe split of an atomic migration/backfill pair;
- false dependency that needlessly serializes work;
- missing dependency that breaks integration;
- public interface change hidden as internal;
- compatibility promise without consumer strategy;
- weak tests that check only status code;
- flaky and non-hermetic required tests;
- contract a trivial wrong implementation can game;
- malicious plan/repository/exemplar instructions;
- two materially different but valid decomposition candidates;
- material amendment affecting one subgraph;
- amendment invalidating a shared interface and many consumers;
- hard cost/time/migration constraint violation;
- insufficient-history simulation that must not emit false precision.

### 16.6 Live planning evaluation

Freeze PlanningSpec inputs and compare at least two configured planning profiles
on a representative corpus. Measure:

- schema-valid proposal rate;
- hard-invariant pass rate before repair;
- human edits and candidate selection;
- scope delta and invented requirements;
- question precision;
- repair rounds and non-progress;
- approval cognitive load;
- downstream generated-Slice success;
- cost and duration.

Do not implement adaptive routing from these results yet.

### 16.7 Downstream execution evaluation

This is the load-bearing compiler eval. Measure:

- generated Slice first-pass and eventual gate success;
- human edits before approval;
- contract disputes during implementation;
- missing context/interface/test findings;
- rework rounds and failure taxonomy;
- cost per approved, successfully executed Slice;
- critic findings confirmed by execution;
- false-positive interrogation questions;
- unnecessary dependency edges and overdecomposition overhead;
- whether the primary and second adapters fail differently on the same contract.

### 16.8 Ablation and controlled studies

Use the Battery and frozen planning corpus to measure:

- Scout on/degraded/off;
- `AGENTS.md` on/off;
- prompt-template versions;
- historical exemplar on/off;
- primary vs second adapter;
- single vs shadow decomposition on high-risk plans;
- Tutor on/off if built;
- Workbench with/without narrative summary;
- typed diff/triage impact on diagnosis time.

These studies produce reports. They do not modify production policy implicitly.

### 16.9 Forecast calibration

When time/cost simulation becomes available, backtest predicted intervals
against actual plan execution. Required reporting:

- p10/p50/p90 coverage;
- error by archetype and confidence class;
- low-sample flags;
- drift over time;
- explicit `insufficient_history` rate.

A poorly calibrated simulator remains advisory or disabled.

### 16.10 Human-legibility evaluation

Give operators labeled tasks:

- identify the highest-risk assumption;
- explain why a Slice exists;
- determine whether attempt B weakened attempt A's contract;
- find which constraint a candidate violates;
- choose the safe recovery action;
- identify what changed after an amendment;
- locate every human verification waiver.

Track task success, time, confidence, and approval reversal. This is the honest
version of a “legibility score.”

## 17. Program KPIs, release gates, and go/no-go thresholds

Averages may guide improvement, but they may not conceal a trust failure. The
program therefore uses two classes of measures:

1. **release-blocking invariants**, where one violation stops the phase; and
2. **calibration measures**, where the first corpus establishes a baseline and
   the retrospective sets the next threshold.

A target that has no empirical basis is labeled a hypothesis. Conveyor must not
turn an attractive round number into fake certainty.

### 17.1 Phase 1.5 qualification gate — hard blockers

`qualification_gate` fails if any of the following is true:

- any enabled Phase-1 gate canary produces a false negative;
- any trust-tool meta-canary produces an incorrect verdict;
- a required TestPack is vacuous, non-hermetic, flaky without an explicit
  fail-closed resolution, or mutable by the implementer;
- a trap case succeeds by weakening tests, changing policy, following an
  untrusted repository instruction, or silently changing the contract;
- the primary live adapter loses required events, cannot be cancelled safely,
  cannot produce an independently captured PatchSet, or misstates its policy
  capabilities;
- a replayed cassette is accepted as fresh authority rather than as recorded
  stochastic input;
- `replay_full` cannot reproduce the recorded conductor projection, or
  `replay_hybrid` changes a known verdict without producing a loud divergence;
- a changed RunSpec accidentally hits an old cassette;
- the Evidence Comparator labels a contract/policy weakening as cosmetic;
- deterministic triage auto-applies a contract, policy, source, or acceptance
  change;
- the MockDegraded conformance adapter (or any second live adapter, when run)
  bypasses the same normalized AgentRunner, policy, evidence, and gate contracts
  used by the primary adapter, or any capability-mismatch branch is left
  unexercised by conformance (R7);
- hidden Battery or challenge oracles are exposed to the implementer;
- the Battery corpus or scoring code cannot be reproduced from content digests;
- any advisory Tutor result can close a Slice or supersede the final gate;
- an old RunAttempt is resumed after a new ContractLock or RunSpec is created.

The phase may also be stopped by a severe adapter, sandbox, artifact-integrity,
or evidence-redaction defect even when it is not represented in the fixed list
above. The list is a floor, not a loophole catalogue.

### 17.2 Phase 1.5 measured qualification baselines

The first complete live Battery establishes, per adapter and archetype:

- first-pass success;
- eventual expected-outcome success;
- attempts and rework rounds;
- wall-clock time and queue time;
- tokens and cost where reported reliably;
- context-pack precision, recall, and miss rate;
- policy-block and contract-dispute rate;
- TestPack integrity failures;
- triage classification accuracy and `unknown` rate;
- Evidence Comparator diagnosis time;
- human intervention minutes;
- diff size and out-of-scope change rate;
- cassette replay coverage and divergence rate;
- adapter event loss, cancellation latency, and cleanup failures.

The initial decision bands are deliberately conservative:

| Result                                                                                    | Interpretation          | Required action                                             |
| ----------------------------------------------------------------------------------------- | ----------------------- | ----------------------------------------------------------- |
| All hard blockers clear; ordinary cases mostly reach expected outcomes; traps fail safely | qualified               | proceed to Phase 2                                          |
| Hard blockers clear, but one archetype or adapter is materially weak                      | conditionally qualified | restrict scope/profile and open a targeted hardening branch |
| Any hard blocker fails, or ordinary cases routinely require manual rescue                 | not qualified           | do not automate decomposition yet                           |

“Mostly” is made rigorous by an explicit statistical acceptance model recorded
in the QualificationGrant (R1) — not by a hand-picked threshold:

- run each archetype k times live (k chosen for the desired confidence width);
- estimate the success rate with a Beta posterior, or run a sequential
  probability ratio test against a floor p₀ (stop early once the posterior
  clears or fails);
- the Grant stores
  `success_rate_band = {p_low, p_high, confidence, k, floor_p0}`, never a single
  observed pass/fail;
- a result below the floor yields a `conditional` Grant scoped to the archetypes
  that cleared, not a global failure.

The decision artifact must state the sample size, confidence limitations, and
any excluded case. Excluding a hard case merely because it failed is prohibited.

### 17.3 Phase 2 contract/compiler gate — hard correctness thresholds

`phase2_gate` fails if any approved plan revision violates any of these:

- less than 100% requirement → acceptance criterion → Slice traceability for
  approved scope;
- any orphan Slice, test, interface, constraint reference, atomicity group, or
  executable dependency edge;
- any cycle in the executable hard-dependency graph;
- any unresolved hard constraint or human decision represented as satisfied;
- any generated scope addition lacking explicit provenance and approval;
- any approved field whose inference class or source cannot be recovered;
- any approved bundle that cannot be reproduced and verified by root digest;
- any approval not bound to the exact PlanRevision, ConstraintSet,
  DecompositionSelection, WorkGraph, contracts, tests, policies, and waivers
  shown to the approver;
- any contract, policy, approval, or plan revision mutated in place;
- any author/critic/Test-Architect/implementer role-separation violation;
- any enabled planning prompt-injection fixture escape;
- any required TestPack with unexplained calibration, integrity, or authority
  failure;
- any public or cross-Slice interface without an explicit stability/lock mode;
- any locked interface consumer/provider pair whose schemas cannot be reconciled
  or whose incompatibility lacks an approved migration plan;
- any future RunPrompt that fails prompt dry-compilation;
- any generated Slice that cannot explain why it is independently verifiable;
- any automatically accepted negotiation that touches an AC, decision, hard
  constraint, authorized scope, or public compatibility promise;
- any new ContractLock/RunSpec that reuses the old RunAttempt;
- any candidate decomposition automatically blended from disagreeing proposals
  without a recorded selection or human decision;
- any mandatory human verification represented as machine-verified;
- any selective amendment recompile that leaves a semantically affected Slice on
  its old digest.

### 17.4 Phase 2 quality targets — hypotheses to calibrate

These are starting targets, not marketing guarantees:

- at least 80% of generated Slices are approved without being rewritten from
  scratch;
- median bounded repair is no more than one round per generated Slice;
- at least 70% first-pass deterministic gate success on the generated-Slice
  sequential pilot;
- material contract-dispute rate below 20% of executed generated Slices;
- no more than one consolidated human clarification batch per PlanRevision,
  unless an answer reveals genuinely new information;
- interrogation hard-finding precision above 80%; false positives and false
  negatives are both sampled;
- 100% of high-impact inferred assumptions are explicitly accepted, rejected, or
  converted into a hard decision before approval;
- every selected decomposition candidate either dominates alternatives on the
  declared constraints or records why the tradeoff was accepted;
- no more than 10% of approved Slices are later coalesced or split because the
  original boundary was not independently verifiable;
- approval reversal caused by hidden scope or inference remains zero in the
  release corpus;
- the Contract Critic catches every planted “cheapest wrong implementation”
  fixture;
- no required challenge case is lost between contract authoring and gate
  execution.

If the corpus demonstrates that a target is poorly chosen, change the target
through a recorded PhaseNextDecision. Do not quietly relabel a miss as a pass.

### 17.5 Human legibility and recovery targets

Operators should be able to complete the following tasks without database access
or raw-log spelunking:

- identify what Conveyor inferred rather than read from the plan;
- identify the highest-impact unresolved assumption or constraint conflict;
- explain why a Slice exists and why its dependencies are necessary;
- compare two decomposition candidates and name the material tradeoff;
- determine whether a retry uses the same contract;
- locate the exact field that made evidence stale;
- find every waived or human-only verification obligation;
- recover the reusable outputs from a failed planning or execution run;
- identify the next safe action and whether it changes authority.

Initial usability hypotheses:

- at least 90% task success on the labeled legibility study;
- median diagnosis under five minutes for a two-attempt failure;
- median approval under 30 minutes for an eight-to-twelve-Slice familiar-domain
  plan;
- zero cases where the UI and static report imply different authority or state;
- zero destructive recovery actions hidden behind a generic “retry” control.

### 17.6 Phase-3 readiness decision matrix

Passing Phase 2 does not automatically authorize a fleet. The retrospective must
evaluate six independent dimensions:

| Dimension             | Ready signal                                                         | Not-ready signal                                           |
| --------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------- |
| Gate integrity        | all canaries/meta-canaries green; no unexplained false green         | any false negative or authority ambiguity                  |
| Contract stability    | low material-dispute and rewrite burden; challenges catch loopholes  | frequent amendments or post-start contract repair          |
| Adapter reliability   | clean cancellation, evidence capture, policy enforcement             | lost events, orphan sandboxes, capability mismatch         |
| Operator clarity      | humans correctly understand scope, assumptions, and recovery         | approval reversals, long diagnosis, UI/report disagreement |
| Sequential execution  | generated Slices pass the real loop without hand-rewriting contracts | manual rescue is routine                                   |
| Economics and latency | measured enough to set bounded concurrency and budgets               | costs/durations are missing or wildly unstable             |

The recorded outcome is one of:

```text
advance_to_phase3
advance_with_restrictions
repeat_targeted_qualification
harden_gate_first
harden_adapter_first
harden_contract_pipeline_first
harden_operator_surface_first
park_program_decision
```

---

## 18. Milestone plan with execution-shaped acceptance criteria

Milestones are deliberately split into **Phase 1.5 qualification** and **Phase 2
compiler/contract work**. Phase 2 implementation work may be prepared in a
branch, but generated-contract authority does not activate until
`qualification_gate` passes.

### P15.0 — Phase-1 retrospective and branch selection

Deliver:

- answer every Phase-1 retrospective question with evidence;
- record gate-canary false negatives, adapter defects, context misses, evidence
  confusion, operator time, and live-agent outcome;
- create `PhaseNextDecision` with the selected branch;
- freeze the Phase-1 artifact/schema versions used as the qualification base.

Acceptance criteria:

- Branch priority is
  `gate > adapter > policy/sandbox > evidence integrity > context > operator clarity > default balanced`;
- every branch selection cites at least one measured signal;
- a stop-the-line branch prevents later authority activation;
- the decision can be regenerated from the referenced evidence.

### P15.0a — End-to-end integration tracer (throwaway, time-boxed)

The program's load-bearing bet — _a machine-generated contract can drive the
qualified loop to green without manual rewrite_ — is otherwise first tested at
P2.11, the penultimate milestone, after ~24 gated milestones of horizontal
infrastructure. That inverts biggest-risk-first (R4). Before committing to the
full build, run one deliberately crude vertical slice end to end.

Deliver:

- pick ONE real Slice in the disposable Battery repo;
- generate its contract from a single one-shot decomposer prompt — **no**
  compiler, critic, Workbench, Test Architect, or approval bundle;
- run the **real** (not fake) Phase-1 loop on it and observe whether it reaches
  a correct gate verdict;
- write a one-page findings note: where the generated contract needed human
  patching, what schema fields were missing, what surprised us.

Acceptance criteria:

- explicitly throwaway and non-production; no code from it is promoted;
- time-boxed (days, not weeks);
- the note feeds the Phase-2 schema freeze (P2.0) and may re-order the branch
  decision (P15.0) — wildly under-specified generated contracts are
  contract-pipeline evidence bought for the price of a spike, not a program;
- it is reviewed before the Phase-2 schema freeze.

### P15.1 — Canonical capability registry and qualification seams

Deliver:

- create `CAPABILITY-REGISTRY.md` and canonical keys;
- resolve both C11–C20 numbering collisions without deleting historical aliases;
- activate or add the minimal seams for archetype, cost, iterative checks,
  context usage, integrity status, rule keys, interface keys, and dispute state;
- add schema compatibility tests.

Acceptance criteria:

- no new ADR, migration, issue, or commit uses an ambiguous `Cxx` as its sole
  identifier;
- old labels resolve to exactly one canonical family plus source document;
- nullable seams remain behaviorally inert until their mechanism is enabled;
- old Phase-1 fixtures still validate.

### P15.2 — Battery corpus and hidden-oracle discipline

Deliver:

- create at least one ordinary case for `crud_endpoint`, `bugfix_regression`,
  `pure_refactor`, `schema_migration`, and `dependency_update`;
- create trap cases for test weakening, impossible acceptance, prompt injection,
  silent behavior drift, policy evasion, and evidence tampering;
- define known expected outcomes and failure classes;
- create a held-out/rotating subset and challenge-oracle access policy;
- content-address every fixture and expected artifact.

Acceptance criteria:

- each case passes plan audit/readiness before the agent runs;
- ordinary cases have independently authored contracts and known-good outcomes;
- trap cases cannot be passed merely by reading the fixture metadata;
- hidden oracles are unavailable to implementer mounts and prompts;
- a fixture mutation changes the corpus digest and invalidates prior summaries.

### P15.3 — Battery runner, scorer, and release report

Deliver:

- `Conveyor.Jobs.RunBattery` with sequential width one;
- BatteryRun/BatteryCaseResult persistence;
- deterministic expected-outcome scorer;
- per-adapter/archetype report;
- `mix conveyor.battery`, `battery_report`, and `battery_gate`.

Acceptance criteria:

- a case failing for the wrong reason fails the Battery;
- ordinary and trap outcomes are reported separately;
- infra failures do not masquerade as model-quality failures;
- rerunning the same fixture/cassette set reproduces the same score;
- the summary includes every excluded or waived case explicitly.

### P15.4 — Primary live-adapter qualification

Deliver:

- run the full Battery with the Phase-1 primary adapter;
- capture normalized events, PatchSet, command/policy evidence, costs where
  available, cancellation, heartbeat, and cleanup behavior;
- test forced cancellation, provider timeout, malformed event, and agent crash.

Acceptance criteria:

- adapter capabilities are recorded rather than assumed;
- cancellation revokes credentials and cleans the sandbox;
- the conductor independently derives the PatchSet and final verdict;
- malformed or missing events fail closed;
- every live run can be promoted to a sealed cassette after integrity checks.

### P15.5 — Second adapter and adapter-conformance suite

Deliver:

- implement a materially different second adapter behind `AgentRunner`;
- run the same conformance fixtures and a representative Battery subset;
- document tool-loop overlap, pre-exec policy posture, resume semantics, and
  capability limitations;
- record an adapter comparison report without declaring a universal winner.

Acceptance criteria:

- no conductor state-machine fork is added for the second adapter;
- hard policy/capability filters precede model selection;
- an observe-only adapter receives a lower autonomy ceiling;
- adapter-specific output normalizes into the same evidence schemas;
- vendor/product changes are isolated in the adapter implementation.

### P15.6 — Agent Cassettes and deterministic replay

Deliver:

- `AgentCassette` resource and seal/invalidity rules;
- `record`, `replay_full`, `replay_hybrid`, and proposal-only replay modes;
- exact RunSpec freshness key;
- replay verification job and CLI;
- retention/redaction policy for recorded stochastic data.

Acceptance criteria:

- any contract, prompt, policy, toolchain, adapter capability, or station-plan
  change misses the cassette;
- full replay reproduces the recorded conductor projection;
- hybrid replay reruns the current deterministic gate against the recorded
  patch;
- a replay divergence is surfaced as a first-class result;
- recorded agent claims are never replayed as gate authority.

### P15.7 — Test Integrity Sentinel and trust-tool meta-canaries

Deliver:

- red-on-stub/vacuity checks;
- hermeticity, order, time, RNG, network, and flake probes;
- quarantine lifecycle with required-test safety rules;
- meta-canaries for the Sentinel, Comparator, Triage, Tutor if enabled,
  BehaviorLock, replay, and escalation;
- expanded gate-canary corpus by archetype.

Acceptance criteria:

- a required flaky/vacuous test blocks readiness until replaced or explicitly
  human-waived; it is not silently removed from authority;
- optional quarantined tests cannot create a false green;
- each trust tool detects its planted failure and passes a clean control;
- one meta-canary miss fails `qualification_gate`;
- canary selection is recorded and full corpus runs at release gate.

### P15.8 — Evidence Time Machine and deterministic triage kernel

Deliver:

- typed diff across RunSpec, contract, prompt, policy, context, PatchSet, gate,
  environment, cassette, and artifact manifest;
- `why_stale`, `diff_runs`, and `diff_artifacts` commands;
- deterministic failure rules and `ReworkRecipe` artifact;
- advisory dossier-only triage reviewer for unresolved cases;
- labeled confusion-matrix eval.

Acceptance criteria:

- weakening and freshness changes classify materially;
- missing/tampered blobs produce `incomparable`, never a partial silent diff;
- low-risk replay/rerun recipes are idempotent and bounded;
- all contract/policy/source-changing recipes require their normal authority
  flow;
- ambiguous fixtures yield `unknown` rather than fabricated confidence.

### P15.9 — Scoped Behavior Lock for the refactor archetype

Deliver:

- one bounded oracle mode for the controlled Battery repo;
- deterministic input corpus and output canonicalization;
- explicit allowed divergences;
- BehaviorLockRun artifact and meta-canaries.

Acceptance criteria:

- a silent behavior drift is detected;
- a genuine behavior-preserving refactor passes;
- an allowed declared divergence is visible and approved;
- inconclusive oracle coverage cannot be presented as a lock.

### P15.10 — Measurement studies and conditional loop improvements

Deliver:

- Scout/AGENTS.md ablation;
- prompt-template A/B;
- adapter/archetype cost-quality comparison;
- optional Gate-as-Tutor shadow trial;
- optional bounded retry-with-escalation shadow trial.

Acceptance criteria:

- studies use the same frozen corpus and disclose sample size;
- no mechanism becomes authoritative solely because one small experiment looks
  favorable;
- Tutor advisory results cannot close Slices;
- escalation never consumes a step for contract or policy failures;
- reports preserve negative or null findings.

### P15.11 — Qualification review and branch closure

Deliver:

- run all hard blockers;
- publish qualification dossier, metrics, known limitations, and residual risks;
- record `qualification_gate` result and PhaseNextDecision;
- either authorize Phase 2 activation or open a targeted hardening tranche.

Acceptance criteria:

- no failed case is omitted from the release report;
- conditional qualification names the exact allowed archetypes/adapters;
- any waiver has an owner, expiry, rationale, and affected authority ceiling;
- the decision is bound to corpus, adapter, gate, and schema digests.

### P2.0 — Phase-2 entry freeze and immutable planning kernel

Deliver:

- verify `qualification_gate` authority;
- add PlanRevision, PlanningSpec, PlanningRun, PlanningBundle, ConstraintSet,
  DecompositionCandidate, DecompositionSelection, and inference provenance;
- extend AgentSession roles without weakening Phase-1 invariants;
- add planning artifact projection and replay.

Acceptance criteria:

- the same frozen PlanningSpec regenerates identical deterministic station
  inputs;
- mutable source changes create a new PlanRevision/PlanningSpec;
- planning approval identity is content-addressed;
- historical Phase-1 evidence remains interpretable.

### P2.1 — Constraint compiler, assumption register, and decision debt

Deliver:

- normalize hard constraints, soft preferences, budgets, forbidden approaches,
  rollout constraints, and human-only decisions;
- distinguish explicit, observed, inferred, and derived fields;
- build contradiction and precedence checks;
- render unresolved decision debt.

Acceptance criteria:

- a hard constraint can never be traded off by a model score;
- conflicting hard constraints block planning with one question batch;
- soft tradeoffs remain visible in candidate comparison;
- high-impact inference cannot disappear inside generated prose;
- every accepted default has provenance, impact, and optional expiry.

### P2.2 — Spec Interrogator and consolidated human decisions

Deliver:

- deterministic structural interrogation;
- separate interrogator profile/prompt/schema;
- one-batch question workflow with proposed defaults;
- HumanDecision resolution and new PlanRevision generation;
- precision/false-negative eval fixtures.

Acceptance criteria:

- contradiction, unbounded requirement, missing non-goal, and hidden dependency
  fixtures are caught;
- a clean plan produces no hard questions;
- a second batch is allowed only when new information is introduced;
- the interrogator asks but never silently edits the plan.

### P2.3 — Repository Planning Context and advisory code-impact overlay

Deliver:

- deterministic repository inventory, instruction/policy map, interfaces, tests,
  ownership hints, migrations, risk domains, and existing constraints;
- optional AST/tree-sitter/LSP symbol and dependency overlay through adapters;
- confidence/provenance on every impact prediction;
- ProjectKnowledgeSnapshot with explicit lifecycle.

Acceptance criteria:

- source observations cite exact commit/path/symbol or report unknown;
- an extractor failure degrades to advisory/unknown rather than inventing an
  impact map;
- project knowledge is inspectable, editable, and digest-bound;
- no context tool mutates source or becomes execution authority.

### P2.4 — Decomposition candidates and deterministic work-graph compiler

Deliver:

- primary Decomposer proposal;
- optional independent shadow candidate for selected high-risk plans;
- candidate identities and comparison rubric;
- deterministic compiler assigning stable IDs and materializing canonical IR;
- explicit candidate selection rather than automatic blending.

Acceptance criteria:

- malformed proposals never become source-of-truth records;
- every selected Slice explains intent, boundary, oracle, and dependency;
- disagreeing alternatives remain visible;
- selected candidate records human or policy rationale;
- identical input/proposal compiles identically.

### P2.5 — Graph validity, typed dependencies, atomicity, and anti-confetti gate

Deliver:

- dependency types: execution-hard, interface, integration-order, verification,
  human-decision, and scheduling hint;
- cycle/orphan/reachability checks;
- atomicity groups;
- split/coalesce quality checks;
- structural graph simulation and critical-path calculation without fabricated
  economics.

Acceptance criteria:

- likely-file overlap alone does not create a hard dependency;
- unsafe atomicity splits are rejected;
- giant Slices and confetti graphs produce actionable findings;
- every node is reachable or explicitly deferred;
- structural simulation is deterministic and labels absent history honestly.

### P2.6 — Contract Forge, interface compatibility, and rollout intent

Deliver:

- upgraded AgentBrief/contract schema;
- current/desired behavior, non-goals, authorized scope, public/cross-Slice
  interfaces, lock modes, error behavior, compatibility expectations, rollout,
  migration safety, and challenge cases;
- archetype templates;
- prompt dry-compilation.

Acceptance criteria:

- internal implementation freedom is preserved unless a genuine architecture
  constraint exists;
- all public/cross-Slice surfaces have provider/consumer ownership and
  compatibility classification;
- deprecation/wrapper proposals are marked as proposals and independently
  verified;
- every contract compiles into a bounded future RunPrompt;
- scope additions require explicit approval.

### P2.7 — Test Architect, calibration, integrity, and conditional strength

Deliver:

- isolated test-only authoring workspace;
- TestSpecification and ChallengeCase schemas;
- red/base and green/reference calibration where a legitimate reference exists;
- integrity sentinel from Phase 1.5;
- adversarial contract review and conditional language mutation adapters;
- human-verification-only representation.

Acceptance criteria:

- Test Architect cannot edit production source;
- tests map to ACs and state expected failure reasons;
- full code mutation is required only when a legitimate independent reference
  exists; otherwise the plan uses integrity, challenge cases, vacuity checks,
  and post-implementation mutation later;
- human verification is never forged into machine evidence;
- weak test packs route back to their author, not the implementer.

### P2.8 — Multi-lens Contract Critic and bounded repair

Deliver:

- separate critic profiles/lenses for intent, principal-engineering boundary,
  interface risk, test strength, reliability, security, cost/complexity, and
  human cognitive load;
- “cheapest wrong implementation” attack;
- bounded repair proposals and non-progress detection;
- preservation of unaffected proposal artifacts.

Acceptance criteria:

- planted loopholes and scope laundering are caught;
- critic disagreement is retained rather than collapsed into fake consensus;
- no repair weakens AC/policy/constraint without human authority;
- oscillating repairs park with evidence;
- partial successful work is reusable after one contract fails.

### P2.9 — Workbench, candidate comparison, approval bundle, and static parity

Deliver:

- Qualification Cockpit and Plan Workbench views;
- intent/constraints, alternatives, graph, impact, inference, contract,
  challenge, risk, recovery, and diff views;
- structured actions rather than direct DB mutation;
- canonical static approval report;
- approval digest binding and progressive disclosure.

Acceptance criteria:

- UI and static report derive from the same canonical bundle;
- an approver can identify every high-impact inference and constraint conflict;
- candidate comparison shows material tradeoffs and scope differences;
- changing one approved byte invalidates approval;
- all actions create normal domain records and ledger events.

### P2.10 — Amendments, staged negotiation, selective invalidation, and recovery

Deliver:

- PlanAmendmentProposal impact analysis;
- material/non-material classifier;
- default human-gated negotiation and shadow adjudication mode;
- optional later pre-attempt auto-accept policy only after measured trust;
- affected-subgraph recompilation;
- typed evidence comparison and recovery recipes.

Acceptance criteria:

- any new lock/spec creates a new attempt;
- non-material status cannot be self-declared by the implementer;
- any AC/decision/hard-constraint/scope/compatibility weakening is material;
- unaffected digests remain stable only when semantic impact analysis proves it;
- old evidence remains valid for its old contract;
- rejected disputes record rationale and abuse signal.

### P2.11 — Sequential generated-plan pilot

Deliver:

- one multi-Epic plan producing roughly 8–12 Slices;
- at least one fork/join, public interface, migration or compatibility concern,
  intentional ambiguity, alternate decomposition, material amendment, and
  human-only verification item;
- approval through the Workbench;
- execution of at least five generated Slices through the qualified Phase-1
  loop, serially;
- retrospective and Factory Chronicle.

Acceptance criteria:

- no human rewrites a contract from scratch after approval merely to make the
  pilot pass;
- every failure produces a typed comparison and safe next action;
- independent Slices continue when an unrelated Slice is parked;
- generated contracts preserve all hard constraints and approved scope;
- final report separates plan/compiler, context, implementation, gate, and
  operator failures.

### P2.12 — Release evaluation and Phase-3 decision

Deliver:

- run all compiler, contract, security, recovery, and legibility suites;
- compare targets with observed data;
- publish limitations and unresolved decision debt;
- record `phase2_gate` and PhaseNextDecision;
- create the Phase-3 entry contract or a targeted hardening plan.

Acceptance criteria:

- every hard correctness invariant passes;
- all waivers are explicit, scoped, expiring, and reflected in autonomy;
- the sequential pilot evidence is attached;
- the Phase-3 decision uses the six-dimension matrix in §17.6;
- no roadmap pressure can override a failed gate without a visible human risk
  acceptance.

---

## 19. Delivery cutline and scope control

The combined program is intentionally ambitious. The following cutline keeps it
implementable while preserving the trust spine.

### `P15_CORE_REQUIRED`

- retrospective branch selection;
- canonical capability registry;
- permanent Battery corpus and runner;
- primary live-adapter qualification;
- second-adapter conformance;
- Agent Cassettes with full/hybrid replay;
- Test Integrity Sentinel;
- expanded canaries and trust-tool meta-canaries;
- Evidence Comparator;
- deterministic triage and qualification gate.

### `P15_TRUST_REQUIRED`

- exact RunSpec cassette freshness;
- hidden-oracle isolation;
- artifact integrity/redaction;
- capability-to-autonomy mapping;
- required-test fail-closed quarantine rules;
- replay authority isolation;
- trap slices for test weakening, prompt injection, impossible AC, and evidence
  tampering;
- reproducible release report.

### `P15_SHOULD_HAVE`

- scoped Behavior Lock for the refactor Battery case;
- Scout/AGENTS.md and prompt-template studies;
- a small Tutor shadow experiment;
- bounded escalation shadow experiment;
- minimal LiveView Qualification Cockpit.

### `P15_DEFER_FIRST`

- real PR creation if it distracts from loop qualification;
- broad adapter catalogue;
- generalized behavior characterization;
- learned routing;
- parallel Battery execution;
- hidden autonomous remediation.

### `P2_CORE_REQUIRED`

- immutable planning kernel;
- ConstraintSet and inference ledger;
- Spec Interrogator;
- repository Planning Context;
- DecompositionCandidate/Selection;
- deterministic WorkGraph compiler;
- typed dependencies, atomicity, and anti-confetti checks;
- Contract Forge;
- Test Architect;
- Contract Critic and bounded repair;
- prompt dry-compilation;
- approval bundle and static report;
- human approval and lock creation;
- amendments and new-attempt semantics;
- sequential generated-plan pilot.

### `P2_TRUST_REQUIRED`

- complete provenance for inferred fields;
- hard-constraint enforcement;
- scope-delta classification;
- role separation;
- bundle-root approval binding;
- planning prompt-injection evals;
- contract/test integrity;
- no circular universal mutation requirement;
- no in-place revisions or same-attempt RunSpec changes;
- safe selective invalidation;
- planning replay/provenance;
- human-verification truthfulness.

### `P2_OPERATOR_REQUIRED`

- candidate comparison;
- inference/constraint/risk-first Workbench views;
- typed Evidence Time Machine;
- deterministic triage/recovery recipes;
- static/headless parity;
- explicit waivers and decision debt;
- partial-result salvage;
- clear permission modes for structured actions.

### `P2_SHOULD_HAVE`

- advisory AST/symbol impact overlay for one or two stacks;
- limited real-reference mutation adapters;
- Contract Chronicle/Factory Story projection;
- semantic scope-delta visualization;
- approval cognitive-load meter;
- selective subgraph recompile optimization.

### `P2_DEFER_FIRST`

- direct manipulation/drag-and-drop planning IDE;
- generic rich Evidence Time Machine visualization beyond the core typed diff;
- automatic contract negotiation during an active attempt;
- cost/duration forecasts before calibrated history exists;
- blocking semantic interface firewall across all languages;
- automatic compatibility-wrapper generation as authority;
- patch shrinker;
- full Gate-as-Tutor mechanism;
- adaptive routing or provider-price arbitrage;
- parallel fleet, merge queue, auto-merge, or deployment;
- self-play, auto-bisect, auto-revert, and Best-of-N;
- hidden persistent memory;
- broad multi-repo orchestration.

Scope-control rule:

> A deferred idea may add a small schema or adapter seam only when the cost is
> demonstrably tiny, the historical data would otherwise be lost, and the seam
> does not create new authority or active lifecycle complexity.

---

## 20. Risks, failure modes, and mitigations

| Risk                                            | Failure mode                                               | Mitigation / release response                                                                                    |
| ----------------------------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Phase 1.5 becomes an endless proving ground     | The product never reaches automated planning               | fixed minimum corpus, explicit exit gate, add cases only for a documented failure class                          |
| Battery overfitting                             | Prompts/adapters memorize nine public fixtures             | held-out rotating cases, hidden challenge oracles, corpus-version tracking, no fixture-specific prompt rules     |
| Fixture leakage                                 | Implementer sees known-good patch or hidden test           | separate mounts/credentials, manifest audit, trap meta-canary, fail release on exposure                          |
| Cassettes create false confidence               | Old stochastic output is mistaken for fresh model quality  | exact RunSpec key, replay labels, live release subset, gate recomputed in hybrid mode                            |
| Replay records unsafe secrets                   | Provider/tool output enters durable artifacts              | redaction before seal, sensitivity labels, retention/expiry, quarantine on scanner failure                       |
| Second adapter drives architecture forks        | Vendor-specific state leaks into conductor                 | strict AgentRunner conformance, normalized events, capability snapshot, adapter-owned integration code           |
| Adapter capabilities are overstated             | Observe-only execution receives high autonomy              | negative capability tests, policy engine hard filters, lower ceiling by default                                  |
| Meta-canaries are too toy-like                  | Trust tools pass fixtures but fail reality                 | mine real escapes over time, include clean controls, periodically challenge the meta-canaries themselves         |
| Required flaky tests are silently dropped       | Gate passes without a contractual oracle                   | required tests block until replaced/waived; quarantine cannot weaken authority invisibly                         |
| Triage becomes an unsafe autonomous editor      | A “recipe” changes contract or source                      | deterministic safe-action allowlist; all other actions route through normal authority flows                      |
| Tutor teaches to a weak subset                  | Agent games advisory checks                                | advisory-only, integrity-verified tests, final-alignment metric, final gate unchanged                            |
| Behavior Lock overclaims completeness           | Small input corpus is called equivalence proof             | scoped oracle declaration, coverage/inconclusive status, no word “proof” in verdict unless formally justified    |
| Automating a bad manual schema                  | Tracer assumptions become permanent                        | qualification across archetypes/repos before compiler freeze; schema changes remain versioned                    |
| Decomposition looks plausible but is wrong      | Human approves polished nonsense                           | deterministic compiler, alternatives, provenance, constraints, challenge cases, sequential pilot                 |
| Alternative proposals overwhelm the human       | More options reduce decision quality                       | generate alternatives only for high-risk/uncertain plans, material-difference summary, default primary candidate |
| Alternatives are blended incoherently           | Hybrid graph has incompatible assumptions                  | no automatic blend; explicit selection or a new compiled candidate with provenance                               |
| Hard and soft constraints blur                  | Model trades away a non-negotiable requirement             | typed ConstraintSet, precedence rules, hard constraints cannot be scored away                                    |
| Inference ledger becomes visual noise           | Humans stop reviewing badges                               | risk/impact-first filtering, collapse low-impact derived fields, measure legibility                              |
| Workbench becomes a planning IDE                | UI scope delays trust kernel                               | projection-first, structured actions, static report parity, direct graph editing deferred                        |
| AST/code-impact overlay is noisy                | False dependency edges serialize work                      | advisory confidence, adapter conformance, no authority unless verified, file overlap remains a hint              |
| Test Architect writes weak tests                | Gate manufactures synthetic trust                          | integrity, challenge cases, independent critic, conditional mutation, held-out post-implementation tests         |
| Mutation-at-lock creates circular reference     | Test author secretly implements the feature                | require legitimate independent reference; otherwise defer code mutation to candidate implementation              |
| Interface locking overconstrains implementation | Agents dispute harmless internal choices                   | lock public/cross-Slice surfaces; use explicit lock levels; internal choices informational by default            |
| Compatibility wrapper proposal is wrong         | “Backward compatible” claim breaks consumers               | treat generator output as proposal; run old/new contract and consumer tests; human approval for public surface   |
| Repair loops burn cost or weaken intent         | Agents oscillate toward an easy contract                   | bounded rounds, semantic diff classes, no automatic weakening, preserve partial good artifacts                   |
| Selective recompilation misses impact           | Stale downstream contract remains approved                 | typed dependency/interface graph, fail closed to wider invalidation when confidence is low                       |
| Stable IDs drift                                | Evidence and links become uninterpretable                  | compiler-owned IDs, supersedes lineage, content digests, no model-assigned source identity                       |
| Human approval becomes ceremonial               | Large bundle gets one-click approval without comprehension | cognitive-load budget, risk/inference-first ordering, Epic tabs under one checkpoint, legibility tests           |
| Interrogator annoys users                       | False questions train humans to click through              | deterministic checks first, precision/recall tracking, soft defaults, one consolidated batch                     |
| Ghost Context causes cargo-cult copying         | Old patch is imitated under different constraints          | exact provenance, same-repo/toolchain filters, show as untrusted exemplar, never replace fresh discovery         |
| Semantic compression loses critical detail      | Agent acts on an inaccurate summary                        | raw-source links, loss checks, confidence, expand-on-demand, never compress authoritative contract text          |
| Forecast theater                                | Sparse data shown as precise cost/time                     | no estimate until history; ranges and confidence; backtest calibration; `insufficient_history` is valid          |
| Schema/resource sprawl                          | Ash model becomes harder than product                      | active resource only for lifecycle/query/authorization; otherwise artifact or embedded schema                    |
| Sensitive planning evidence leaks               | Plans, code maps, or failures expose secrets               | sensitivity labels, redaction, access policy, projection filtering, retention rules                              |
| Phase 2 silently becomes Phase 3                | Scheduler/merge work consumes the compiler phase           | explicit cutline, structural simulation only, PhaseNextDecision required for authority expansion                 |
| Roadmap idea bank becomes commitment            | Ambitious concepts inflate current scope                   | every idea has phase, prerequisite, evidence trigger, and “not authority yet” status                             |

Residual-risk rule: every accepted release waiver records owner, scope, expiry,
reason, compensating control, and autonomy ceiling. Permanent “temporary”
waivers are prohibited.

---

## 21. Canonical capability registry

The source plans reuse `C11–C20` for different capabilities. New work must use
stable semantic keys. Historical labels remain aliases for provenance, never
primary identifiers.

### 21.1 Registry schema

```text
capability_key
canonical_name
aliases[]                  # source document + legacy C-number
purpose
primary_phase
status ∈ proposed | seam_only | active | qualified | deferred | retired
depends_on[]
schema_refs[]
adr_refs[]
metrics[]
authority_effect
owner
```

A registry entry is versioned and content-addressed. Renaming a display label
must not change `capability_key`.

### 21.2 Canonical families

| Capability key             | Canonical name                                   | Primary placement            |
| -------------------------- | ------------------------------------------------ | ---------------------------- |
| `TRUST-BATTERY`            | Full-loop Qualification Battery                  | Phase 1.5                    |
| `AGENT-CASSETTES`          | Recorded Stochastic Input and Replay             | Phase 1.5                    |
| `ADAPTER-QUALIFICATION`    | AgentRunner Conformance and Capability Truth     | Phase 1.5                    |
| `TEST-INTEGRITY`           | Contract Test Integrity Sentinel                 | Phase 1.5/2                  |
| `EVIDENCE-FORENSICS`       | Evidence Time Machine and Typed Diff             | Phase 1.5+                   |
| `FAILURE-TRIAGE`           | Deterministic Triage and Recovery Recipes        | Phase 1.5+                   |
| `BEHAVIOR-LOCK`            | Scoped Differential Behavior Guard               | Phase 1.5 seed / Phase 4     |
| `GATE-TUTOR`               | Continuous Advisory Verification Feedback        | Phase 4                      |
| `PLAN-INTERROGATION`       | Spec Interrogator                                | Phase 2                      |
| `CONSTRAINT-COMPILER`      | Hard/Soft Constraint and Decision Compiler       | Phase 2                      |
| `PLAN-WORKBENCH`           | Executable Plan Decision Surface                 | Phase 2                      |
| `DECOMPOSITION-CANDIDATES` | Alternative Work-Graph Proposals and Selection   | Phase 2                      |
| `PLAN-SIMULATION`          | Structural then Calibrated Plan/Swarm Simulation | Phase 2 seam / Phase 3–6     |
| `CODE-IMPACT`              | Advisory AST/Symbol/Interface Impact Overlay     | Phase 2 advisory / Phase 3–4 |
| `CONTRACT-QUALITY`         | Contract Forge, Test Architect, Strength Checks  | Phase 2                      |
| `CONTRACT-EVOLUTION`       | Amendments and Staged Negotiation                | Phase 2                      |
| `INTERFACE-RISK`           | Semantic Interface Firewall and Compatibility    | Phase 3–4                    |
| `RECOVERY-KERNEL`          | Partial Salvage, Continuation, and Safe Actions  | Phase 1.5–2                  |
| `FACTORY-CHRONICLE`        | Evidence-Grounded Story and Learning Summary     | Phase 2 projection           |
| `GATE-LEARNING`            | Regression Mutants, Self-Play, Lessons-to-Rules  | Phase 5–7                    |
| `AUTONOMY-READINESS`       | Merge Trust and Readiness Control Center         | Phase 3–6                    |
| `MODEL-ROUTING`            | Outcome Router and Agent Skill Graph             | Phase 7                      |
| `SCOUT-LEARNING`           | Self-Training Context Scout                      | Phase 7                      |
| `PROJECT-KNOWLEDGE`        | Inspectable, Editable Project Memory             | Phase 2 seam / Phase 7       |
| `TRUNK-GUARDIAN`           | Auto-Bisect and Auto-Revert                      | Phase 5                      |
| `SPECULATIVE-EXECUTION`    | Best-of-N and Gate Arbitration                   | Phase 5–6                    |
| `PATCH-MINIMIZATION`       | Gate-Preserving Patch Shrinker                   | Phase 4–5                    |
| `VERIFICATION-PLANNING`    | Test Impact and Risk-Proportional Gate           | Phase 4–6                    |
| `MIGRATION-SAFETY`         | Migration Rehearsal and Semantic Restoration     | Phase 4/product track        |
| `ROLLOUT-SAFETY`           | Feature Flags, Dark Launch, and Canary Promotion | Phase 5/product track        |
| `BROWNFIELD-SAFETY`        | Onboarding, Trace-to-Contract, Golden Master     | post-Phase 4 track           |
| `PRODUCT-GATE`             | Standalone PR Reviewer                           | post-Phase 4 track           |
| `HUMAN-ATTENTION`          | Expected-Value Human Attention Queue             | Phase 6                      |
| `PERMISSION-MODES`         | Inspect, Suggest, and Trusted Execution Policies | Phase 1.5+                   |

Registry law:

> Documentation may refer to a legacy C-number only alongside its canonical key
> and source. Schemas, code modules, ADRs, metrics, tickets, and commits use the
> canonical key.

---

## 22. What should follow the combined program

The default successor is **Phase 3 — Parallel Fleet and Merge Queue**, but only
when §17.6 records `advance_to_phase3` or a precisely restricted variant.

### 22.1 Phase 3 minimum scope

1. dependency-aware Dispatcher and bounded WorkerPool;
2. one isolated workspace/container per attempt;
3. serialized merge queue into `dev` with fresh gate execution;
4. conflict and interface-impact advisory checks;
5. structural simulation upgraded with measured station distributions;
6. operator readiness dashboard and circuit breakers;
7. no auto-merge beyond the authority earned by the qualification data.

### 22.2 Conditional successors when Phase 2 exposes a different bottleneck

- **Gate-first hardening:** strengthen canaries, integrity, behavior lock, and
  post-implementation mutation before concurrency.
- **Adapter-first hardening:** repair cancellation, policy interception,
  evidence capture, or sandbox lifecycle before adding workers.
- **Contract-pipeline hardening:** improve interrogation, constraints,
  decomposition boundaries, or Test Architect quality before scaling output.
- **Context-first hardening:** improve Planning Context/Scout recall when
  generated work is correct but implementers lack the right code knowledge.
- **Operator-first hardening:** improve comparison, approval, and recovery when
  humans cannot confidently supervise even serial work.
- **Product-track diversion:** ship a standalone deterministic gate/contract
  linter only when it does not weaken the factory critical path.

### 22.3 Later default roadmap

- **Phase 4 — Verification Pyramid:** Epic/phase gates, behavior lock at scale,
  post-implementation mutation, test-impact planning, interface firewall,
  blast-radius verification, deterministic fault injection, and mature Tutor.
- **Phase 5 — Self-Healing and Trunk Safety:** retry/supervisor policy,
  regression-mutant minting, shadow self-play, auto-bisect/revert, rollout
  guardrails, and restricted low-risk auto-merge.
- **Phase 6 — Economics and Human Attention:** Governor, calibrated simulation,
  expected-value attention queue, budget envelopes, and controlled speculative
  execution.
- **Phase 7 — Compounding Learning:** model routing, Scout learning, inspectable
  project memory, prompt optimization, and lessons graduating to deterministic
  rules.
- **Phase 8 — Interface-Driven Throughput:** stub-based parallelism, richer
  multi-repo/interface orchestration, and advanced integration planning after
  the earlier gates prove trustworthy.

Do not pull self-play, auto-revert, adaptive routing, or Best-of-N forward
merely because they demo well. Each amplifies the authority of earlier
components and therefore inherits their defects.

---

## 23. The strongest ideas in one page

- **Qualify the real loop before automating its inputs.** Phase 1.5 turns the
  full agent loop into a permanent Battery rather than trusting one happy-path
  tracer.
- **Record stochastic behavior; recompute authority.** Cassettes make real-agent
  behavior replayable without replaying the agent’s claims as truth.
- **Every trust tool gets a meta-canary.** The Sentinel, Comparator, Triage,
  Behavior Lock, Tutor, replay layer, and gate must prove they detect their own
  planted failures.
- **Start Phase 2 through evidence-driven branch routing.** Gate or adapter
  defects outrank attractive compiler work.
- **Compile constraints, not just prose.** Hard constraints cannot be traded
  away; soft preferences remain explicit tradeoffs.
- **Show what Conveyor invented.** The inference ledger, assumption register,
  confidence, and decision debt make generated plans inspectable.
- **Alternatives are decision surfaces, not hidden model debate.** High-risk
  plans may receive independent candidates; Conveyor never silently blends
  disagreeing assumptions.
- **Agents propose; deterministic code materializes.** Models never write
  execution truth directly.
- **A good graph is neither a monolith nor confetti.** Atomicity, independent
  oracles, fixed station overhead, and typed edges govern Slice size.
- **Interfaces coordinate only where coordination is real.** Public and
  cross-Slice surfaces are explicit; internal implementation stays free.
- **The Test Architect is separate and sandboxed.** Tests are mapped to ACs,
  integrity-checked, challenged, and read-only to implementers.
- **Attack the cheapest wrong implementation.** The Contract Critic asks how a
  bad implementation could game the exact written contract.
- **Mutation is evidence, not theater.** Full code mutation at lock time is
  conditional on a legitimate independent reference; otherwise it follows the
  candidate implementation.
- **No new RunSpec in an old attempt.** Contract evolution always creates a new
  lock, spec, and attempt, while preserving historical evidence.
- **The Workbench is a decision and recovery surface.** It compares candidates,
  constraints, inference, risk, challenge coverage, and impact; it is not a
  second source of truth.
- **Failures preserve useful work.** Typed triage, evidence diffing, partial
  salvage, and smart continuation prevent all-or-nothing reruns.
- **Static/headless parity is mandatory.** The CLI report and UI show the same
  canonical state and authority.
- **Forecast only after calibration.** Before history, Conveyor shows graph
  structure and uncertainty—not fictional cost precision.
- **Generated plans earn a fleet by surviving serial execution.** Parallelism is
  the reward for stable contracts, not the method used to discover whether they
  are stable.

---

## 24. Additional high-leverage ideas considered

These ideas are deliberately separated from current authority. Each can be
promoted only when its prerequisite evidence exists and its complexity is worth
the operational burden.

### 24.1 Static archetype contract templates — recommended for core

Use a small controlled vocabulary and minimum obligations rather than asking a
model to reinvent contract structure every time.

| Archetype            | Required contract obligations                                                        |
| -------------------- | ------------------------------------------------------------------------------------ |
| `bugfix_regression`  | reproduction test, cause hypothesis, unchanged-behavior list                         |
| `crud_endpoint`      | request/response interface, negative status cases, persistence reflection            |
| `schema_migration`   | forward/backward compatibility, data preservation, rollback/irreversibility decision |
| `pure_refactor`      | behavior-preservation oracle, public-interface freeze, no feature ACs                |
| `dependency_update`  | lockfile scope, advisory/security rationale, regression and rollback plan            |
| `security_hardening` | threat scenario, abuse case, negative tests, mandatory security review               |
| `performance`        | workload, baseline, threshold, variance policy, regression budget                    |
| `configuration`      | default, override precedence, invalid value behavior, secret handling                |

Templates are deterministic policy, not hidden prompt lore. `custom` remains
possible but increases critic and approval scrutiny.

### 24.2 Anti-overdecomposition budget — recommended for core

Reject both giant Slices and confetti graphs. Consider Slice count, edge
density, shared likely files, shared oracles, fixed station overhead,
fan-in/fan-out, risk-domain crossings, and whether a Slice has an independent
gate.

Stable findings include:

```text
slice_too_large
slice_too_small_to_justify_run
coordination_overhead_dominates
false_parallelism
shared_oracle_prevents_independent_verification
risk_domains_should_split
```

The objective is minimum total expected work and maximum independent
verifiability—not the smallest possible task.

### 24.3 Atomicity groups — recommended for core

Model work that must remain together:

```text
atomicity_group_key
reason
members[]
policy ∈ same_slice | same_epic_gate | same_integration_batch
```

Examples include schema plus data backfill, authorization plus audit logging,
and transaction write plus outbox event. This prevents apparently tidy graphs
from creating unsafe intermediate states.

### 24.4 Contract falsifiability proof — recommended for critic rubric

For every AC, provide at least one concrete counterexample that should fail. If
no counterexample can be articulated, the AC is probably tautological,
aesthetic, or not machine-verifiable.

### 24.5 Alternate-decomposition shadow pass — selective experiment

For high-risk or highly uncertain plans, run a second independent Decomposer and
compare requirement coverage, boundaries, edges, interfaces, atomicity, and
risk. Do not merge automatically. Show material disagreement and let the human
select or request a new synthesized candidate whose assumptions are explicit.

### 24.6 Slice coalescer/splitter — later Phase-2 optimization

Propose graph patches that merge Slices sharing one oracle/working set, split
Slices spanning risk or interface domains, or downgrade false hard dependencies
to scheduling hints. It proposes; the compiler validates; the human sees any
material scope or contract change.

### 24.7 Approval cognitive-load budget — recommended metric

Estimate review burden from inferred facts, high-risk surfaces, unresolved
warnings, critic disagreement, contract length, candidate count, and revision
delta. When the budget is exceeded, improve summarization or segment the same
approval checkpoint into Epic-focused views. Do not pretend a 200-Slice
one-click approval was meaningful.

### 24.8 Semantic scope-delta detector — recommended

Classify source intent versus generated graph:

```text
scope_preserved
scope_added
scope_removed
scope_reinterpreted
unknown
```

Every `scope_added` item requires provenance and explicit approval.

### 24.9 Contract challenge cases — recommended

Preserve adversarial situations created by the critic. Some become executable
hidden tests; others remain human-review scenarios. They seed later red-team,
mutation, behavior-lock, and escaped-defect corpora.

### 24.10 Interface consistency solver — later

Validate that structured provider and consumer contracts agree on identity,
version, schema, errors, compatibility, lifecycle, and ownership. Start with a
simple deterministic schema unifier; do not build a general theorem prover.

### 24.11 Human approval signatures — later trust upgrade

Phase 2 binds approval to a digest. Teams and remote runners may later add local
key or Sigstore-compatible signatures. This improves attribution, not semantic
correctness, so it should not delay the local OSS path.

### 24.12 “Why this Slice?” capsule — recommended

Every Slice gets a concise compiler-generated explanation of why it is separate,
what verifies it, what it unlocks, why each dependency exists, and what would be
lost by merging it with neighbors.

### 24.13 Decision-debt meter — recommended projection

Track accepted defaults and deferred decisions embedded in active contracts.
High-impact, high-age decision debt can block autonomy or force re-approval.

### 24.14 Planning SARIF export — cheap integration

Export plan/contract findings as SARIF so IDEs and CI can show source-linked
problems. This is an adoption nicety, not source of truth.

### 24.15 Contract lint as a standalone command — likely high ROI

```bash
mix conveyor.plan_prepare PLAN.md --no-agents
mix conveyor.contract_lint agent_brief.yml
```

A deterministic-only mode can become an adoption wedge without creating a
separate architecture.

### 24.16 Decomposition confidence calibration — learning seam

Record confidence per proposed Slice, edge, interface, and inference, then
compare with human edits, disputes, and downstream failures. Confidence is a
calibration signal, never authority.

### 24.17 Contract provenance graph — later visualization

Render which plan paragraphs, decisions, repository observations, constraints,
and agent inferences produced each field. Phase 2 begins with source badges and
links; a specialized graph UI waits for demonstrated need.

### 24.18 Approval shadow predictor — defer

A model might predict which inferred items a human will reject. Do not make this
a priority before enough approval history exists; risk-first deterministic
ordering is safer and simpler.

### 24.19 Code Impact Overlay — advisory Phase-2/3 accelerator

Project the proposed Slices onto current modules, symbols, call edges, routes,
tables, events, tests, and ownership hints using language-specific adapters.
Show:

- predicted symbols touched;
- provider/consumer relationships;
- test and migration proximity;
- confidence and extractor version;
- conflicting candidate overlays.

The overlay must never create a hard dependency solely from an uncertain AST or
call-graph edge. Its primary value is human intuition, context scouting, and
future interface-risk planning.

### 24.20 Compatibility Bridge and Deprecation Planner — later proposal engine

When an approved public interface change is intentional, propose versioned
routes, adapters, translation layers, deprecation warnings, and removal dates.
The output is a contract/patch proposal, not a guarantee. Existing-client tests,
old/new schema checks, and explicit lifecycle policy determine whether it is
safe.

### 24.21 Ghost Context / Evidence-Grounded Exemplars — guarded later feature

For a difficult archetype, retrieve prior successful dossiers, symbol maps,
minimal diffs, and failure lessons from the same project or a trusted template.
Every exemplar is:

- provenance-labeled and content-addressed;
- filtered by language/toolchain/interface similarity;
- treated as untrusted context, not instruction;
- checked for stale constraints;
- paired with fresh repository discovery.

This can reduce rediscovery without turning old solutions into cargo-cult code.

### 24.22 Deterministic Fault-Injection Profiles — Phase-4/5 verification

Replace vague “Chaos Monkey agent” behavior with reproducible profiles:

```text
network_unavailable
provider_timeout
database_connection_drop
worker_process_kill
disk_full_boundary
clock_jump
rate_limit_response
malformed_dependency_payload
```

Each profile has a seed, scope, expected resilience behavior, cleanup contract,
and safety policy. Randomness without replayable evidence is not a gate.

### 24.23 Ephemeral Staging Environments — later integration surface

Materialize an Epic candidate into a short-lived, isolated environment with
pinned image, sanitized seed data, configuration digest, and preview URL. Use it
for integration/e2e, human verification, and dark launch rehearsal. The
environment is an artifact of a gate—not a production deployment shortcut.

### 24.24 Migration Rehearsal Lab — high-value product track

For schema/data migrations, run against a sanitized or synthetic production-like
clone and verify:

- forward migration;
- application compatibility during rollout;
- backfill idempotency and data invariants;
- rollback where semantically possible;
- restore-from-backup when rollback is not possible;
- lock/downtime and performance budgets;
- old/new binary compatibility.

A syntactic down migration is not sufficient evidence of reversibility.

### 24.25 Architecture Decision Tournament — selective, human-decided

For genuinely high-impact decisions, solicit independent proposals from lenses
such as reliability, simplicity, security, operability, and cost. Require each
to state assumptions, evidence, rejected alternatives, and migration cost. A
critic compares the tradeoffs; the human or an already-approved policy decides.
No voting or “consensus score” becomes architectural truth.

### 24.26 AST-Aware Semantic Merge Assistant — advisory first

Classify conflicts by symbol and intent, then propose a parse-valid merge or
reapplication plan. It may explain that one side renamed a function while the
other changed its body, or that two migrations need ordering. Every proposal is
materialized in a clean workspace and reruns the full integration gate. Textual
Git remains the source mechanism; semantic assistance does not bypass the merge
queue.

### 24.27 Feature-Flag and Dark-Launch Rollout — later authority layer

For behavior-changing work, contracts may declare feature-flag strategy,
shadow/read-only execution, canary percentage, success/error thresholds, and
instant disable behavior. This reduces rollback latency, but requires external
runtime telemetry, explicit deployment authority, and cleanup of stale flags.

### 24.28 AST-Guided Context Compression — experimental

Compress large files into symbol signatures, invariants, call summaries, and
relevant spans while preserving raw-source links. Validate compression against
known questions and expand on uncertainty. Never compress contracts, policies,
or exact error/test evidence where wording is authoritative.

### 24.29 Provider Economics and Availability Routing — Phase 6/7

Record provider/model price, latency, rate limits, capability, policy posture,
and observed outcome. Route only after hard capability and trust filters.
Price/latency failover can be useful, but “real-time commodity hedging” is not a
core requirement and should not introduce operational churn or weaker privacy
posture.

### 24.30 Factory Chronicle and Academy — low-risk delight layer

Generate an evidence-grounded narrative after qualification, planning, and
execution:

- what the human asked for;
- what Conveyor inferred and the human decided;
- which candidate was selected and why;
- what changed, passed, failed, and was recovered;
- what the factory learned;
- the safest next actions.

This is a projection over recorded evidence, not a claim to reveal private model
reasoning. It can double as onboarding/tutorial material and institutional
memory.

### 24.31 Standalone Gate and Contract Reviewer — post-Phase-4 product wedge

Package deterministic plan/contract linting and the stable verification gate for
ordinary human PRs. It can expand adoption and generate real defect data, but it
must consume the same kernel rather than fork into a second product.

### 24.32 Inspectable Project and User Memory — later, explicit only

Add project conventions, approved decisions, recurring risks, and user defaults
as editable, provenance-labeled records with scope, confidence, TTL, and delete
controls. Hidden sticky memory is prohibited. Derived summaries must link back
to source evidence and be invalidated when contradicted.

### 24.33 Tool Contracts and Permission Modes — recommended platform seam

Every tool declares input/output schema, side effects, idempotency, policy
profile, retry semantics, data sensitivity, and capability requirements. Expose
three operator modes:

```text
inspect     read-only analysis and artifacts
suggest     prepare exact actions for approval
execute     perform pre-authorized bounded actions
```

The mode is part of RunSpec/PlanningSpec and cannot be inferred from UI context.

### 24.34 Smart Continuation — recovery-oriented product behavior

When a run stops, derive a small set of state-aware next actions: revise one
constraint, rerun one station, compare candidates, promote a partial artifact,
open an amendment, or park safely. Suggestions cite the evidence and authority
required; they are not generic engagement prompts.

### 24.35 Partial Artifact Promotion and Branching — later workbench feature

Allow a useful test specification, interface contract, research note,
characterization corpus, or context pack from a failed proposal to be promoted
into a new planning revision. Preserve lineage and avoid forcing the user to
repeat good work because one downstream step failed.

### 24.36 Multi-repository contract graph — defer until single-repo trust

Represent services and libraries with explicit versioned interfaces, ownership,
release order, and environment constraints. This is valuable for real systems
but multiplies identity, credential, and rollout complexity; it should follow a
proven interface firewall and merge queue.

---

## 25. Alternative sequencing considered

### Alternative A — go directly to Phase 3 fleet

**Rejected as the default.** It delivers visible parallelism quickly but scales
an unqualified loop and unproven contract stream. It is the best demo path and
the wrong trust path.

### Alternative B — build the full verification pyramid next

**Tempting but incomplete.** A stronger gate matters, but its input contracts
and real-agent loop still need qualification. Phase 1.5 pulls forward the
minimum integrity/behavior/forensics pieces; the full pyramid remains Phase 4.

### Alternative C — build a standalone PR reviewer next

**Strong adoption wedge, wrong immediate critical path.** It may run as a small
parallel product track after the gate stabilizes, but it does not replace the
plan-to-contract compiler.

### Alternative D — build brownfield onboarding next

**Strategically important, premature as the core successor.** Real repositories
are the market, but safe characterization, behavior lock, migration rehearsal,
and interface extraction need a mature gate. Qualification may include selected
real repos without promising automated onboarding.

### Alternative E — build only a read-only Workbench next

**Too UI-heavy.** A Workbench without canonical IR, constraints, provenance, and
a compiler is a polished view of untrusted suggestions.

### Alternative F — build only the Decomposer next

**Too stochastic.** Decomposition without interrogation, constraints, test
architecture, adversarial criticism, and approval evidence simply converts
ambiguity into authoritative-looking JSON.

### Alternative G — stop after Phase 1.5 for an extended period

**A valid contingency, not the default.** If the Battery exposes severe adapter
or gate defects, continuing to harden N=1 is correct. The exit condition is the
qualification gate, not a calendar date.

### Alternative H — add limited parallelism inside Phase 2

**Rejected for production authority; allowed only as test infrastructure.**
Independent planning jobs and read-only critic passes may run concurrently, but
generated implementation Slices remain serial until Phase 3.

### Alternative I — build project memory and a broad agentic workspace first

**Useful product direction, wrong authority order.** First-class artifacts,
state, comparison, and recovery are integrated now; persistent learning/memory
waits until provenance, correction, and trust semantics are mature.

### Alternative J — adapter-first or gate-first hardening

**Conditionally preferred when the retrospective fires that branch.** This is
not a competing roadmap but a stop-the-line rule: if the foundation is weak,
repair it before Phase 2.

### Recommended default sequence

```text
finish Phase 0/1
→ throwaway end-to-end integration tracer (one generated contract → real loop)
→ retrospective and branch selection
→ Phase 1.5 Battery qualification
→ targeted hardening if required
→ Phase 2 Plan Compiler & Contract Foundry
→ sequential generated-Slice pilot
→ evidence-based Phase-3 decision
```

---

## 26. Product and operator experience principles

The system should feel like an inspectable factory for work, not a chat thread
with hidden automation.

### 26.1 Work state and artifacts are first-class

Every PlanRevision, candidate, graph, constraint, contract, test pack, run,
comparison, decision, recovery recipe, and approved result is a durable artifact
with lineage. Users can leave, return, compare, branch, and export without
reconstructing state from conversation history.

### 26.2 Uncertainty is operational

Avoid generic confidence badges. Show:

- which fields are explicit, observed, inferred, or derived;
- which assumptions would change the graph or acceptance criteria;
- where extractors or agents disagree;
- what cannot be verified automatically;
- what evidence would resolve the uncertainty.

### 26.3 Alternatives are native when uncertainty is real

Serial iteration remains the default. Competing candidates are used selectively
for consequential ambiguity, then presented as a decision surface with material
differences—not as a wall of prose.

### 26.4 Recovery is designed before the happy-path polish

A failed station should preserve reusable outputs, explain what failed and why,
offer bounded safe actions, and state which downstream artifacts became stale.
Restarting the entire plan is a last resort.

### 26.5 Permissions are visible and scoped

The user can tell whether Conveyor is inspecting, suggesting, or executing.
Every consequential action states its scope, side effects, evidence, and
required authority. “Approve” never means “also merge/deploy.”

### 26.6 Progressive disclosure, not hidden complexity

Default views show intent, blockers, high-risk inference, candidate tradeoffs,
and next actions. Exact schemas, logs, digests, and provenance remain one click
or one CLI command away.

### 26.7 Static and headless parity

Anything needed to approve, diagnose, or recover is available through canonical
artifacts and CLI. LiveView improves navigation; it does not create exclusive
state or authority.

### 26.8 Project knowledge is inspectable and correctable

Conventions, prior decisions, and learned lessons must be visible, scoped,
versioned, and editable. A correction invalidates derived summaries and future
PlanningSpecs that depended on it.

### 26.9 One platform, graduated power

Advanced users may receive larger plans, richer comparison, more adapters, or
higher autonomy, but the architecture must remain the same. Do not create a
separate “premium” control plane with different trust semantics.

### 26.10 Delight follows truth

Risk heatmaps, stories, tutorials, graph animation, and one-click actions are
valuable only when they project canonical evidence accurately. Product polish
must make authority easier to understand, never disguise uncertainty.

---

## 27. Future architecture seams and roadmap contracts

This section records what the combined program must leave possible without
implementing it prematurely.

### 27.1 Phase 3 seam contract — parallel fleet and merge queue

Phase 2 must leave:

- stable ready-pool queries;
- typed hard and scheduling dependencies;
- interface/provider-consumer identities;
- conflict domains and likely symbols/files;
- immutable RunSpecs per attempt;
- adapter capability snapshots;
- bounded concurrency and budget hooks;
- merge-ready evidence bundles;
- circuit-breaker and cancellation events.

Phase 3 adds authority only after the Dispatcher and merge queue independently
recheck readiness and gate freshness.

### 27.2 Phase 4 seam contract — verification pyramid

Contracts must support:

- Slice/Epic/Phase gate level;
- required and deferred suites;
- challenge/held-out tests;
- mutation and behavior-lock target scopes;
- interface/compatibility checks;
- blast-radius and test-impact data;
- deterministic fault-injection profiles;
- performance/security/rollout requirements.

### 27.3 Phase 5 seam contract — self-healing and trunk safety

The ledger must distinguish:

- implementation failure;
- contract failure;
- policy failure;
- infrastructure failure;
- merge/integration failure;
- escaped defect;
- rollout failure;
- human decision block.

Each must map to bounded retry, escalation, revert, flag disable, mutant mint,
or park behavior without conflating them.

### 27.4 Phase 6 seam contract — economics and attention

Record from the start:

- cost and duration by station, adapter, model, archetype, and outcome;
- critical-path/unblock data;
- human effort and wait time;
- verification cost;
- simulation prediction versus actual;
- budget consumption and cancellation reason.

No Governor may optimize cost ahead of hard policy, gate integrity, or quality
floors.

### 27.5 Phase 7 seam contract — learning and memory

Preserve:

- stable failure/rule keys;
- context usage;
- candidate confidence versus human edits;
- routing outcomes;
- accepted/rejected defaults;
- escaped defects and remediation;
- project-knowledge provenance.

Learning outputs begin advisory, pass held-out evaluation, and graduate to
deterministic rules only through explicit policy.

### 27.6 Product-track seams

- **Standalone gate:** stable, repository-agnostic verification contract.
- **Brownfield onboarding:** characterization corpus, redaction, and behavior
  lock.
- **Migration lab:** data fixtures, backup/restore, compatibility and downtime
  budgets.
- **Rollout safety:** feature flag, telemetry, canary, and disable contracts.
- **Multi-repo:** explicit service/interface/release graph and credential
  boundaries.

Each track consumes the same evidence, policy, artifact, and authority model.

---

## 28. Recommended engineering workstreams and dependency order

The milestones can be organized into six workstreams, with limited parallelism
that does not compromise the critical path.

### Workstream A — Trust qualification spine

```text
P15.0 → P15.2 → P15.3 → P15.4 → P15.7 → P15.11
```

Owns the Battery, gate honesty, integrity, and release decision. This is the
critical path.

### Workstream B — Adapter and replay substrate

```text
P15.1 → P15.4 → P15.5
              ↘ P15.6
```

May proceed beside corpus construction after schemas freeze. Cassettes require a
qualified normalized event/PatchSet shape, not a perfect model outcome.

### Workstream C — Forensics and recovery

```text
P15.3 → P15.8 → P2.10
```

Start early because every failure in later work becomes cheaper to diagnose. The
deterministic comparator should precede a rich UI.

### Workstream D — Planning compiler

```text
P2.0 → P2.1 → P2.2 → P2.3 → P2.4 → P2.5
```

Constraint and provenance semantics precede Decomposer authority. Repository
impact adapters may be developed in parallel but remain advisory.

### Workstream E — Contract quality

```text
P2.5 → P2.6 → P2.7 → P2.8
```

The Contract Forge and Test Architect can prototype against fixture graphs, but
approval authority waits for the canonical compiler and role policies.

### Workstream F — Operator surface and pilot

```text
P2.4/P2.6/P2.8 → P2.9 → P2.10 → P2.11 → P2.12
```

Build static bundle/report first, then LiveView. The pilot is the integration
test for every workstream.

### 28.1 Safe implementation parallelism

The following may proceed concurrently:

- Battery fixture authoring and adapter-conformance harness;
- cassette storage/replay and Evidence Comparator;
- constraint schema and repository-impact adapter prototypes;
- static approval report and low-level graph projection;
- independent eval fixture creation.

The following must not race conceptually:

- capability/schema naming before the registry freeze;
- ContractLock semantics before contract evolution is settled;
- UI actions before domain actions exist;
- auto-adjudication before materiality evals pass;
- forecasts before history and calibration exist;
- fleet work before both release gates.

### 28.2 Required ADRs before implementation

At minimum:

1. **ADR — Phase 1.5 insertion and release gates**;
2. **ADR — Agent Cassette authority and freshness semantics**;
3. **ADR — required-test quarantine behavior**;
4. **ADR — canonical capability registry**;
5. **ADR — ConstraintSet precedence and inference provenance**;
6. **ADR — DecompositionCandidate selection/no automatic blending**;
7. **ADR — interface lock modes and compatibility authority**;
8. **ADR — contract mutation timing/reference-solution policy**;
9. **ADR — contract evolution always creates a new attempt**;
10. **ADR — static/UI projection parity and permission modes**.

### 28.3 Work-package quality rule

Every implementation Slice in this program must state:

- the release invariant it advances;
- its exact source and artifact schemas;
- deterministic versus agentic responsibility;
- canary/meta-canary;
- rollback or disable path;
- observability and evidence output;
- non-goals and deferred ideas;
- the next downstream milestone it unlocks.

---

## 29. Implementation-start checklist and final recommendation

Before beginning the combined plan:

- [ ] Phase 0/1 Definition of Done is met and its retrospective evidence is
      complete.
- [ ] The original Phase-1 schemas, gate version, canary suite, toolchain image,
      and adapter capability snapshot are frozen by digest.
- [ ] `CAPABILITY-REGISTRY.md` exists and all new work uses canonical keys.
- [ ] The PhaseNextDecision branch is recorded.
- [ ] Battery fixture authors and hidden-oracle maintainers are separated from
      implementer access where practical.
- [ ] Primary and secondary adapter profiles declare honest policy/cancellation
      capabilities.
- [ ] Artifact sensitivity, redaction, retention, and cassette-expiry policies
      are configured.
- [ ] Release-blocking canaries and meta-canaries are named in CI.
- [ ] Required-test quarantine and waiver policy is approved.
- [ ] Contract evolution/new-attempt semantics are covered by database and
      state-machine tests.
- [ ] Workbench actions map to explicit domain actions and permission modes.
- [ ] Phase 3 work is blocked on both `qualification_gate` and `phase2_gate`.

### Final recommendation

Implement this as one coordinated program with two independently shippable
tranches:

1. **Phase 1.5 — Trust Qualification:** prove the real single-Slice factory on a
   permanent Battery, make stochastic runs replayable, qualify adapters, and
   make failures diagnosable.
2. **Phase 2 — Plan Compiler & Contract Foundry:** compile explicit human
   intent, constraints, repository evidence, and bounded agent proposals into an
   approved executable work graph whose generated contracts survive real serial
   execution.

The central strategic choice remains unchanged but is now better defended:

> **Do not scale the number of agents until Conveyor has proven both the loop it
> will multiply and the contracts it will feed into that loop.**

That sequence gives the project the best chance of becoming powerful without
becoming opaque, autonomous without becoming reckless, and ambitious without
building complexity faster than evidence can justify it.
