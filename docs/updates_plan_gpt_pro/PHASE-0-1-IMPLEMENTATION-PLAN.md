# Conveyor — Phase 0 + Phase 1 Implementation Plan

> **Purpose of this document.** A comprehensive, standalone implementation plan for the
> first two phases of Conveyor — the foundations (Phase 0) and the single-Slice "tracer
> bullet" (Phase 1). It is the revised hybrid version after comparing multiple competing
> architecture proposals and the existing Conveyor strategy notes. The revision keeps the
> BEAM/Ash evidence-first spine, but adds the missing product-kernel surface: plan
> readiness, requirement traceability, safety policy, project instructions, adapter
> boundaries, evidence exports, and early swarm-readiness instrumentation.
>
> **Status:** design / pre-implementation. Companion to `docs/BRAINSTORM.md` (the living
> strategy doc with the full architecture and decision log). This document is intentionally
> more implementation-shaped than the brainstorm: it should be detailed enough for agents
> or humans to execute Phases 0 and 1 without rediscovering the architecture.

---

## 0. One-paragraph context

**Conveyor** is an AI-first software factory on the Elixir/BEAM. A human does research,
brainstorming, taste, architecture, and final intent authoring, then hands Conveyor a
high-quality plan. Conveyor turns that plan into a dependency-ordered, contract-bearing
work graph and runs AI coding agents in **isolated containers**, recording every attempt
as immutable evidence, gating the output through deterministic verification and external
review, and learning from the results. It is the autonomous, BEAM-native successor to
*Conveyor AI* (a Go CLI that proved the single-run loop). The guiding bets are:
**isolation over coordination**, **the verification gate is the human's stand-in**,
**agents produce bounded execution, not authority**, and **the deterministic conductor
owns truth while stochastic agents own generation and judgment**.

This document covers the first two phases only. Later phases add automated decomposition,
parallel fleet execution, a merge queue, tiered verification, self-healing, economic
control, institutional memory, and throughput upgrades. Phase 0/1 must nevertheless lay
clean seams for those future capabilities, because retrofitting evidence, policy,
traceability, and adapter boundaries after agents are already running is exactly how these
systems become fragile.

---

## 0.1 What changed in this revision

The original plan was directionally right: BEAM/Ash is the correct control-plane substrate,
recorded evidence is the correct trust primitive, and Phase 1 should be a single-Slice
tracer bullet rather than a premature swarm. The strongest revisions are:

1. **A factory kernel, not a giant platform.** Phase 0/1 now includes only the small set of
   primitives that make every later phase safer: config, doctor checks, plan audit,
   project instructions, policies, evidence, adapters, and gate honesty. We explicitly do
   not rebuild an issue tracker, chat system, LLM framework, static analyzer, or
   deployment platform.
2. **Plan quality becomes a first-class gate.** A Slice should not reach an agent merely
   because a human typed a Brief. Phase 1 adds `PlanAudit`, `Requirement`,
   `HumanDecision`, and requirement-to-Slice traceability, even though decomposition stays
   manual. This tests the future plan compiler without building it yet.
3. **Autonomy is staged and measurable.** The north star remains true autonomous factory
   operation, but the first public promise is verified work packets and human-approved
   merges. Autonomy level is modeled from day one so authority can increase only after
   evidence proves the gate is trustworthy.
4. **Safety policy is not deferred.** Phase 1 runs in Docker, but Docker is not enough.
   The conductor also owns policy profiles, forbidden command classes, environment
   allowlists, workspace boundaries, and incident records.
5. **CodeScent becomes a conductor-run scout and gate stage.** Agents may benefit from
   CodeScent context later, but Phase 1 uses it primarily from the deterministic
   conductor: before work to produce a cited Context Pack and after work to detect risk
   deltas. CodeScent recommendations are context and risk signals, not proof.
6. **The CLI/operator surface starts early.** LiveView is valuable, but an OSS-friendly
   factory also needs crisp commands: doctor, plan audit, seed, run, verify, canary, and
   report. In Phase 0/1 these can be Mix tasks; later they can become a standalone CLI.
7. **Evidence exports are product artifacts, not debug logs.** Every run writes a machine
   manifest, human dossier, diff patch, command logs, CodeScent result, review, and PR-body
   draft under `.conveyor/runs/`. Postgres remains source of truth; disk is a projection.
8. **Swarm readiness is instrumented before swarm execution.** Phase 1 remains one Slice,
   but it records the fields needed later for scheduler scoring, conflict heatmaps, agent
   reputation, stale-run detection, and the swarm dry-run simulator.

---

## 0.2 Product contract and autonomy line

The first public promise should be:

> **Conveyor converts a human-approved plan into coordinated, verified implementation
> work packets, with evidence strong enough to support pull requests and eventually
> low-risk auto-merge.**

Do **not** initially promise "fully autonomous software development" or "agents coding
and deploying 24/7." The long-term vision can be true autonomy, but the implementation
path must earn authority through measured trust.

Autonomy is modeled as a policy dial:

| Level | Name | Authority allowed |
|---:|---|---|
| L0 | Planning only | Audit plans, draft Slices, identify risks, propose tests. No code edits. |
| L1 | Local implementation | Produce diffs in isolated workspaces/containers. No PR creation. |
| L2 | PR generation | Create PR-ready evidence packets and draft PR bodies. Human merge. |
| L3 | Auto-merge low-risk | Auto-merge only low-risk, green, well-scoped Slices through the merge queue. |
| L4 | Auto-deploy | Deploy only after repo-specific trust, phase gates, and explicit release policy. |

**Phase 1 target:** L1 with L2-shaped artifacts. The run produces a PR-quality evidence
packet and PR-body draft, but merge remains a manual human action. This is safer, more
credible for open source, and still proves the core loop.

---

## 1. Goals & non-goals for Phase 0 + 1

### Goals

1. Stand up the **deterministic Elixir core**: an Ash/Postgres domain, append-only ledger,
   durable Oban jobs, policy resources, and the Slice lifecycle as a formal state machine.
2. Establish the **factory kernel surface**: config, doctor checks, seed/import commands,
   plan audit, AGENTS.md generation/linting, run/report commands, and evidence exports.
3. Run **exactly one Slice end-to-end** against a sterile sample Python app, through every
   station of the loop:
   `plan audit → readiness → context scout → run prompt → policy-bounded Pi implementer
   in Docker → evidence → deterministic run-check → reviewer-on-dossier → gate → manual
   merge → retrospective.`
4. **Prove the loop feels right** on a real change and — critically — **prove the gate can
   be made honest** via a gate-canary harness that measures false negatives now, not in a
   later phase.
5. Prove trustworthy agent-TDD: acceptance tests are authored outside the implementer,
   locked before implementation, independently re-run by the conductor, and mapped back to
   acceptance criteria.
6. Establish the **`AgentRunner` adapter** so Pi can later be swapped for Cursor CLI,
   Codex, Claude Code, OpenCode, OpenHands, Aider, Goose, or other agents without changing
   the conductor's core state machine.
7. Make **requirement-to-Slice traceability** real in miniature: every Slice maps back to a
   plan requirement or explicit human decision, and every requirement in the Phase-1 plan
   is either covered, declared out-of-scope, or flagged.
8. Produce durable **evidence packets** and a human-readable dossier that are good enough
   to attach to a PR in a later phase.

### Non-goals (explicitly deferred)

- **No parallel Dispatcher / WorkerPool fleet** — Phase 3. Phase 1 runs one Slice.
- **No fully automated decomposition or multi-model planning** — Phase 2. In Phase 1 the
  human hand-authors the single Plan/Epic/Slice/Brief and failing tests; the conductor
  audits them.
- **No merge queue** — Phase 3. Merge is manual in Phase 1.
- **No autonomous self-healing, economic governor, institutional memory, or agent
  reputation routing** — Phases 5–7. Phase 1 records the data those features will need.
- **No interface-stub parallelism** — Phase 8. Strict dependencies only.
- **No new issue tracker, chat system, static analyzer, LLM framework, or deployment
  platform.** Conveyor should orchestrate boring infra and integrate tools, not recreate
  the whole ecosystem.
- **No auto-deploy.** Deployment authority is deliberately outside Phase 0/1.
- **No broad multi-repo orchestration.** One sample repo, one Slice, one run.

### Definition of done for Phase 1

A human seeds one Plan with one Epic, one Slice, one Agent Brief, and failing pytest cases;
`mix conveyor.plan_audit` reports the plan as handoff-ready; one run action drives the
Slice through every station; Pi produces a diff inside a policy-bounded Docker container;
the conductor independently re-runs pytest and CodeScent; `RunCheck` validates the
manifest/dossier; a separate reviewer judges the recorded dossier; the deterministic gate
passes; the gate-canary rejects a labeled injected-bug set; LiveView and a generated report
show the full timeline; a PR-body draft and evidence packet are written to disk; the human
merges manually; and the run is replayable from the event log.

---

## 2. Tech stack & assumptions

| Concern | Phase 0/1 choice | Why |
|---|---|---|
| Language / runtime | Elixir ~1.17+, Erlang/OTP 26+ | Best fit for durable supervision, concurrent orchestration, and self-healing later. |
| Web / dashboard | Phoenix 1.8.x + LiveView | Minimal real-time run viewer, parked/rework triage later. |
| Domain & persistence | Ash 3.x + AshPostgres, `ash_state_machine`, Postgres 16 | One coherent source of truth; policies and state transitions are enforceable. |
| Background / durable jobs | Oban | Durable stations; crash/reboot resumes from last persisted state. |
| Operator CLI | Mix tasks in Phase 0/1 (`mix conveyor.*`) | Fastest way to ship doctor/audit/run/report without a second CLI project. |
| Agent isolation | Docker container per run | Blast-radius control, reproducible agent and gate environments, clean teardown. |
| Workspace model | Materialized repo checkout inside the container, from a known base commit | Equivalent to a one-task workspace; future phases can use worktrees plus containers. |
| First implementer | **Pi** (`pi.dev`) over RPC/JSON via a BEAM Port | Structured seam, no TUI scraping, minimal orchestration overlap. |
| Future agent seam | `AgentRunner` behaviour + `AgentProfile` capabilities | Keeps Claude/Codex/OpenHands/OpenCode/etc. interchangeable. |
| Code intelligence | **CodeScent** invoked by the conductor | Read-only context/risk/gate signal; no source mutation. |
| Safety | `ExecPolicy` + Docker + environment allowlist + command denylist | Docker is necessary but not sufficient; policy is explicit from day one. |
| Project instructions | Generated/linted `AGENTS.md` | Predictable agent-readable contract for repo commands, rules, and done criteria. |
| Sample testbed | Tiny FastAPI "tasks" service with pytest | Small enough to reason about; rich enough for API behavior, persistence, tests, and mutants. |
| Artifact projection | `.conveyor/runs/<run_id>/` | Reviewable OSS-friendly artifacts while Postgres remains truth. |

**Assumptions:** Docker is installed and reachable; the Pi image contains Pi and the Python
toolchain; an OpenAI/Codex provider credential is available in a scoped way; CodeScent is
installed and runnable in the conductor/gate environment; the sample repo starts from a
known committed base; no production secrets or network-only dependencies are required.

---

## 3. Design laws

These laws are intentionally stricter than ordinary agent workflows. They should be tested
as invariants, not treated as aspirational prose.

1. **No task without acceptance criteria.** A Slice that cannot be verified is too vague or
   too large.
2. **No implementation without a locked contract.** The implementer may not weaken or edit
   acceptance tests, required tests, risk policy, or done definition.
3. **No completion without evidence.** Agent self-report is not evidence. The conductor
   independently records evidence.
4. **No authority without measured trust.** Autonomy level increases only after the gate's
   false-negative rate, review outcomes, and rollback/bug metrics justify it.
5. **No hidden state.** Every material transition and gate result appends a `LedgerEvent`.
6. **No shared-trunk chaos.** Phase 1 uses one isolated container; later phases use one
   task → one workspace/container → one evidence packet → merge queue.
7. **No source mutation by context tools.** CodeScent and scouts may write their own cache
   or `.codescent/` state, but they do not edit source.
8. **No dangerous commands by default.** Docker constrains blast radius; `ExecPolicy`
   constrains intent.
9. **No orphan requirements and no orphan Slices.** Requirements map forward to Slices;
   Slices map back to requirements, decisions, bugs, or explicit improvements.
10. **No bespoke tool empire.** Conveyor should build the conductor and evidence loop;
    existing agents, git, Docker, CodeScent, linters, test runners, and CI do the boring
    work.

---

## 4. Architecture overview

```text
Human Plan + Decisions
        │
        ▼
Plan Audit / Traceability Gate
        │
        ▼
Ash Work Graph + Contracts
        │
        ▼
RunSlice Oban Job
        │
        ├── Readiness
        ├── Context Scout (rg + CodeScent + optional read-only agent pass)
        ├── Prompt Builder (Brief + Pack + AGENTS.md + Policy + output schema)
        ├── AgentRunner.Pi (Docker + RPC + heartbeat + streamed events)
        ├── Evidence Recorder (independent tests + CodeScent + diff + logs)
        ├── RunCheck (manifest/dossier/schema consistency)
        ├── Reviewer-on-Dossier (separate actor/model)
        ├── Deterministic Gate
        ├── Gate Canary Harness
        └── Retrospective / Failure Taxonomy
        │
        ▼
LiveView + `.conveyor/runs/<run_id>/` dossier + PR-body draft
```

Phase 0/1 is deliberately not a swarm. It is the smallest real factory loop with the
right trust boundaries. Parallelism only becomes valuable after this loop proves gate
honesty, artifact quality, and adapter stability.

---

## 5. The determinism boundary

Inherited from Conveyor AI's ADR 0004, restated for the BEAM:

> **The deterministic BEAM conductor owns** paths, state transitions, dependency integrity,
> policy enforcement, validation, prompt assembly, recorded evidence, and the gate
> verdict's mechanical parts. **Agents own** drafting, implementation, and judgment
> (review). When an agent supplies judgment, that verdict is recorded and itself validated
> by the conductor. Agents are never the source of truth for whether something passed.

Concretely in Phase 1:

- The implementer may run tests while coding, but those results are advisory.
- The conductor independently re-runs the gate in a clean container against the produced
  diff.
- The reviewer reads the recorded dossier, not the live session.
- The gate uses the review as one stage, but the conductor validates review schema,
  actor separation, artifact integrity, and deterministic pass/fail mechanics.
- If the agent claims success and the conductor cannot reproduce it, the run fails.

---

## 6. Ash domain model

Phase 0 lays more domain surface than Phase 1 exercises. That is intentional: the schema
should establish stable seams for future decomposition, parallelism, policy, and learning
without forcing those features into the tracer bullet.

### 6.1 Active Phase 0/1 resources

- **`Project`** — `id, name, repo_url?, local_path, default_branch, dev_branch?,
  test_commands[], build_commands[], lint_commands[], codescent_profile,
  default_autonomy_level, status`
- **`Plan`** — `id, project_id, title, intent, source_document, status, readiness_score,
  imported_at`
- **`Requirement`** — `id, plan_id, stable_key, text, section_ref, status∈covered/
  deferred/out_of_scope/open, risk, notes`
- **`HumanDecision`** — `id, plan_id, stable_key, decision, rationale, status, supersedes?`
- **`PlanAudit`** — `id, plan_id, score, decision∈ready/needs_clarification/blocked,
  findings[], coverage_summary, created_at`
- **`Epic`** — `id, plan_id, title, description, risk, approval_status, status`
- **`Slice`** — `id, epic_id, title, position, risk, state, autonomy_level, source_refs[],
  likely_files[], conflict_domains[]`
- **`AgentBrief`** (the contract) — `id, slice_id, version, current_behavior,
  desired_behavior, key_interfaces, out_of_scope, risk, acceptance_criteria[],
  required_tests[], verification_commands[], non_goals[], locked_at, locked_by`
- **`ContextPack`** — `id, slice_id, scout_version, confidence, relevant_files[],
  key_interfaces[], existing_tests[], risks[], suggested_validation[], codescent_refs[]`
- **`RunPrompt`** — `id, slice_id, brief_id, context_pack_id, template_version, body,
  policy_refs[], memory_refs[], output_schema_version`
- **`AgentProfile`** — `id, adapter, provider, model, capabilities, policy_profile,
  enabled, notes`
- **`AgentRun`** — `id, slice_id, run_prompt_id, agent_profile_id, base_commit,
  head_commit, workspace_state, started_at, completed_at, status∈running/succeeded/
  failed/cancelled, outcome∈none/needs_rework/accepted, cost_estimate, tokens?`
- **`Evidence`** — `id, agent_run_id, changed_files[], diff_ref, commands[],
  acceptance_results[], codescent_result_ref, risks[], summary, pr_body_ref`
- **`Review`** — `id, agent_run_id, reviewer_profile_id, reviewed_at,
  decision∈accepted/needs_rework/rejected, recommendation∈merge/rework/ask_human/
  archive, summary, findings[], checks[]`
- **`GateResult`** — `id, agent_run_id, level∈slice, passed, stages[], false_negative?`
- **`CanaryMutant`** — `id, project_id, name, description, patch_ref, expected_failure,
  enabled`
- **`CanaryRun`** — `id, gate_result_id?, mutant_id, passed_when_should_fail,
  stage_that_caught_it?, notes`
- **`Artifact`** — `id, agent_run_id?, kind, path, sha256, size_bytes, created_at`
- **`LedgerEvent`** — `id, project_id, slice_id?, agent_run_id?, type, payload, occurred_at`
- **`Policy`** — `id, name, profile∈explore/implement/verify/release/dangerous_maintenance,
  allowlist, denylist, env_policy, network_policy, autonomy_ceiling`
- **`Incident`** — `id, project_id, slice_id?, agent_run_id?, severity, category,
  description, evidence_refs[], status`

### 6.2 Stub resources created now, exercised later

- **`Workspace`** — future worktree/container assignment record for parallel fleet.
- **`TaskClaim`** — future multi-agent claim semantics.
- **`MergeQueueItem`** — future dev/main integration queue.
- **`BudgetLedger`** — future economic governor.
- **`AgentReputation`** — future model/adapter routing based on empirical success.
- **`Memory`** — future pgvector/institutional memory recall.
- **`ExternalTaskRef`** — future adapter to Beads, GitHub Issues, Linear, etc.

### 6.3 Embedded schemas

`acceptance_criteria[]`:

```elixir
%{
  id: "ac-001",
  text: "PATCH /tasks/{id} with completed=true returns 200 and updated task",
  kind: :behavioral,
  requirement_refs: ["REQ-003"],
  required_test_refs: ["tests/test_tasks.py::test_complete_task"],
  evidence_status: :missing | :passed | :failed | :skipped,
  evidence_refs: []
}
```

`commands[]`:

```elixir
%{
  command: "pytest -q",
  profile: :verify,
  required: true,
  exit_code: 0,
  duration_ms: 1382,
  stdout_ref: "artifacts/stdout.log",
  stderr_ref: "artifacts/stderr.log"
}
```

`findings[]`:

```elixir
%{
  severity: :blocking | :warning | :note,
  category: :brief | :context | :execution | :validation | :review | :policy,
  message: "Reviewer could not map AC-002 to evidence",
  artifact_refs: []
}
```

### 6.4 Artifact storage decision

Postgres is the source of truth for state, relationships, policy, and events. Disk is a
read-only projection for inspectability and PR attachment.

```text
.conveyor/
  config.toml
  policies/
    implement.toml
    verify.toml
  prompts/
    implementation-prompt@1.md
    reviewer@1.md
  runs/
    run_<id>/
      manifest.json
      dossier.md
      evidence.json
      review.json
      gate.json
      pr_body.md
      diff.patch
      commands/
        pytest.stdout.log
        pytest.stderr.log
      codescent/
        before.json
        after.json
      canary/
        mutants.json
```

Projection regeneration must be idempotent: the same run record should recreate the same
artifact tree and checksums.

---

## 7. State machines

### 7.1 Plan state

```text
draft ─▶ audited ─▶ handoff_ready ─▶ active ─▶ completed
  │          │              │
  │          └──────────────┴──▶ needs_clarification
  └────────────────────────────▶ archived
```

A Phase-1 plan can be manually authored, but it still must pass audit before the Slice can
run. This prevents the bad habit of treating manual input as automatically executable.

### 7.2 Slice state

```text
drafted ─▶ approved ─▶ ready ─▶ scouting ─▶ scouted ─▶ prompt_built
   ▲                                                        │
   │                                                        ▼
   │                                                  implementing
   │                                                        │
   │                                                        ▼
   │                                                evidence_recorded
   │                                                        │
   │                                                        ▼
   │                                                     reviewed
   │                                                        │
   │                                                        ▼
   │                                                     gated
   │                                                        │
   │                                                        ▼
   │                                                  integrated
   │                                                        │
   │                                                        ▼
   └────────────────────────────────────────────────────── done

Off-ramps from agent/gate stations:
needs_rework · parked · failed · policy_blocked
```

The original state machine is extended with `reviewed` and `policy_blocked` because Phase
1 now treats reviewer schema/actor separation and policy enforcement as first-class
states, not merely stage details.

```elixir
defmodule Conveyor.Work.Slice do
  use Ash.Resource,
    domain: Conveyor.Work,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:drafted, :approved]
    default_initial_state :drafted

    transitions do
      transition :approve,        from: :drafted,            to: :approved
      transition :mark_ready,     from: :approved,           to: :ready
      transition :start_scout,    from: :ready,              to: :scouting
      transition :scouted,        from: :scouting,           to: :scouted
      transition :build_prompt,   from: :scouted,            to: :prompt_built
      transition :implement,      from: :prompt_built,       to: :implementing
      transition :record,         from: :implementing,       to: :evidence_recorded
      transition :review,         from: :evidence_recorded,  to: :reviewed
      transition :gate,           from: :reviewed,           to: :gated
      transition :integrate,      from: :gated,              to: :integrated
      transition :complete,       from: :integrated,         to: :done

      transition :rework, from: [:reviewed, :gated, :evidence_recorded, :implementing], to: :needs_rework
      transition :park,   from: :*, to: :parked
      transition :fail,   from: :*, to: :failed
      transition :policy_block, from: [:prompt_built, :implementing, :evidence_recorded], to: :policy_blocked
    end
  end
end
```

Every transition writes a `LedgerEvent`; guards validate plan readiness, Brief lock status,
actor separation, required artifacts, gate stage completeness, and autonomy policy.

---

## 8. OTP / Oban topology

```text
Conveyor.Application
├── Conveyor.Repo                                 (AshPostgres)
├── Oban                                          (durable station jobs)
├── ConveyorWeb.Endpoint                          (Phoenix + LiveView)
└── Conveyor.Conductor.Supervisor
    ├── Conveyor.Ledger                           (append-only event writer + PubSub)
    ├── Conveyor.Config                           (runtime config + project config loader)
    ├── Conveyor.Policy.Engine                    (ExecPolicy decisions + incident creation)
    ├── Conveyor.Artifacts.Projector              (Postgres → `.conveyor/runs/*`)
    └── Oban workers
        ├── Conveyor.Jobs.RunSlice                (station orchestrator)
        ├── Conveyor.Jobs.ContextScout            (rg + CodeScent + optional read-only pass)
        ├── Conveyor.Jobs.RunImplementer          (AgentRunner.Pi in Docker)
        ├── Conveyor.Jobs.RecordEvidence          (independent gate command execution)
        ├── Conveyor.Jobs.RunReviewer             (reviewer-on-dossier)
        ├── Conveyor.Jobs.RunGate                 (deterministic gate composition)
        ├── Conveyor.Jobs.RunGateCanary           (mutant gate-only checks)
        └── Conveyor.Jobs.ProjectArtifacts        (manifest/report regeneration)
```

A single `RunSlice` job advances a Slice station by station, but each long-running station
is an Oban job with idempotent inputs and outputs. This gives crash/reboot recovery from
Phase 1 without pretending Phase 1 already has full autonomous retry logic.

---

## 9. Operator interface in Phase 0/1

Use Mix tasks first. Keep command names close to a future standalone `conveyor` CLI.

```bash
mix conveyor.init SAMPLE_PROJECT_PATH
mix conveyor.doctor
mix conveyor.plan_audit PLAN.md
mix conveyor.seed_sample
mix conveyor.show SLICE_ID
mix conveyor.run_slice SLICE_ID
mix conveyor.verify RUN_ID
mix conveyor.gate_canary PROJECT_ID
mix conveyor.report RUN_ID
mix conveyor.replay RUN_ID
```

### 9.1 `mix conveyor.doctor`

Checks:

```text
Elixir/Erlang versions
Postgres connectivity
Oban configured
Docker reachable
Pi image available
Provider credential present and scoped
CodeScent executable available
Git available
Sample repo clean at expected base commit
AGENTS.md present and lint-clean
Test commands configured
Policy profiles configured
Artifact projection directory writable
No production-looking secrets mounted into worker containers
```

Doctor failures should be actionable. A missing optional future adapter is a warning; a
missing Docker daemon, CodeScent executable, policy profile, or test command is a failure.

### 9.2 `mix conveyor.plan_audit PLAN.md`

Outputs a readiness score plus blocking findings:

```text
Clarity: 92%
Acceptance coverage: 100%
Testability: 100%
Requirement traceability: 100%
Architecture decisions: ready
Autonomy readiness: L1/L2-shaped artifacts only
Decision: handoff_ready
```

Findings categories:

```text
missing acceptance criteria
missing required tests
unmeasurable wording
unresolved architecture decision
requirement with no Slice/Brief coverage
Slice with no source requirement/decision
risk without review policy
likely files missing for conflict prediction
verification commands missing or non-reproducible
```

### 9.3 `mix conveyor.report RUN_ID`

Regenerates `dossier.md`, `manifest.json`, `evidence.json`, `review.json`, `gate.json`,
`diff.patch`, and `pr_body.md`. The report should be useful even outside LiveView.

---

## 10. Plan readiness and traceability

Even in Phase 1, the plan compiler is tested as a deterministic audit rather than an
agentic generator. The human still writes the plan and Brief; Conveyor checks whether the
handoff is executable.

A Phase-1 plan must include:

```markdown
# Project Goal
# Non-goals
# User Stories / Requirements
# Technical Architecture
# Constraints
# Risk Areas
# Acceptance Criteria
# Test Strategy
# Verification Commands
# Explicit Human Decisions
# Out-of-scope Items
```

Traceability rules:

- Every `Requirement` has a stable key (`REQ-001`) and source section.
- Every acceptance criterion maps to one or more requirements.
- Every required test maps to one or more acceptance criteria.
- Every Slice maps back to a requirement, human decision, bug, or explicit improvement.
- A requirement may be `covered`, `deferred`, `out_of_scope`, or `open`; `open` blocks
  handoff-ready status.
- The audit does not need to be smart in Phase 1; it needs to be strict, deterministic,
  and loud about ambiguity.

The plan audit is the smallest seed of the later plan-to-task compiler and swarm simulator:
it begins collecting likely files, conflict domains, verification commands, risk level,
and autonomy ceiling before the scheduler exists.

---

## 11. Project instructions: `AGENTS.md`

Phase 0 generates and lints an agent-readable `AGENTS.md`. This is not optional: the
factory should not hand a repo to any coding agent without a clear, repo-local contract.

Minimum generated structure:

```markdown
# Project Overview

# Architecture Map

# Commands
- Install:
- Build:
- Test:
- Typecheck:
- Lint:
- Run app:

# Coding Rules

# Testing Rules

# Security Rules

# Git Rules

# Task Rules

# Done Criteria

# Forbidden Actions

# How to Use Conveyor Evidence

# How to Use CodeScent Context

# How to Report Blockers
```

The `AGENTS.md` linter checks:

- required command sections are present;
- commands match `Project.test_commands` / `build_commands` / `lint_commands`;
- done criteria mention evidence and independent verification;
- forbidden actions align with `Policy` denylist;
- instructions do not contradict the sample repo's configured commands;
- security rules explicitly forbid production secrets and deployments in Phase 1;
- ambiguous terms like "make it good" or "mobile-friendly" are absent unless defined by
  measurable acceptance criteria.

---

## 12. Safety and policy layer

Docker limits blast radius; policy limits intent. Both are required.

### 12.1 Policy profiles

```text
explore     read/search/context only; no source edits
implement   source edits allowed inside workspace; no dangerous git/fs/network/deploy
verify      run build/test/lint/CodeScent; no source edits except tool-owned cache
release     future only; deployment commands require explicit repo policy
maintenance future only; dangerous commands require human approval and incident log
```

### 12.2 Minimum denylist

```text
rm -rf outside mounted workspace
git reset --hard
git clean -fd / -fdx
git push --force / --force-with-lease
chmod/chown outside workspace
curl | sh, wget | sh
sudo commands inside worker
access to ~/.ssh, cloud credentials, production env files
production database URLs
package installs outside the container image or project venv
network calls except allowlisted package registries/provider APIs
any deploy command at autonomy levels L0-L2
```

A policy violation creates an `Incident`, stops the run, records evidence, and moves the
Slice to `policy_blocked` or `failed` depending on severity. Policy false positives are
acceptable in Phase 1; silent policy bypasses are not.

---

## 13. Context Scout and CodeScent integration

`ContextScout` is a read-only station. Its job is to reduce agent confusion before the
implementer gets edit authority.

Phase-1 scout inputs:

- Plan, Requirement, HumanDecision, Slice, and AgentBrief.
- `AGENTS.md` and project config.
- `rg`/file tree results.
- CodeScent repo status, search/risk/smell outputs available from CLI/MCP.
- Existing tests and likely affected modules.

Context Pack output:

```json
{
  "slice_id": "slice_123",
  "confidence": 0.86,
  "relevant_files": [
    {"path": "app/main.py", "reason": "Defines current task routes"},
    {"path": "tests/test_tasks.py", "reason": "Existing API behavior tests"}
  ],
  "key_interfaces": ["PATCH /tasks/{id}", "Task.completed"],
  "existing_tests": ["tests/test_tasks.py"],
  "risks": ["In-memory persistence must preserve completed state across list calls"],
  "suggested_validation": ["pytest -q"],
  "codescent": {
    "baseline_ref": "artifacts/codescent/before.json",
    "new_work_should_not_increase_high_risk_findings": true
  }
}
```

CodeScent is used in three places:

1. **Before work:** identify relevant files, existing smells/risks, and suggested tests.
2. **After work:** detect risk deltas and new findings.
3. **Gate:** block if configured thresholds are violated.

CodeScent output is never treated as sole proof. The gate still runs tests, validates the
manifest, and requires reviewer acceptance.

---

## 14. Prompt envelope

`PromptBuilder` creates a versioned prompt from structured inputs. The prompt should be
boring, bounded, and explicit.

Required sections:

```markdown
# Role
You are the implementer for exactly one Conveyor Slice.

# Autonomy Level
L1: local implementation only. Do not create PRs, merge, deploy, or modify policy.

# Project Instructions
<AGENTS.md excerpt or reference>

# Slice Contract
<AgentBrief: current behavior, desired behavior, key interfaces, ACs, required tests, out-of-scope>

# Context Pack
<cited relevant files, risks, existing tests, CodeScent notes>

# Safety Policy
<allowed commands, forbidden commands, network/env limits>

# Work Rules
- Keep the change minimal.
- Do not weaken tests.
- Do not edit `.conveyor/`, policy, or locked contracts.
- Stop and report blocker if acceptance criteria are impossible.

# Required Verification
<commands from AgentBrief / Project config>

# Required Output Schema
<summary, files_changed, commands_attempted, acceptance_mapping, known_risks, blocker?>
```

Prompts are immutable artifacts. Prompt template versions are recorded so later learning
can compare outcomes across template revisions.

---

## 15. AgentRunner adapter + Pi over RPC

```elixir
defmodule Conveyor.AgentRunner do
  @moduledoc "Behaviour every coding-agent backend implements."

  @callback capabilities() :: Conveyor.Agents.Capabilities.t()

  @callback run(
              run_prompt :: Conveyor.Work.RunPrompt.t(),
              workspace :: Conveyor.Workspace.Materialized.t(),
              policy :: Conveyor.Policy.PolicyProfile.t(),
              opts :: keyword()
            ) :: {:ok, Conveyor.Work.RawRunResult.t()} | {:error, term()}

  @callback cancel(session_id :: String.t()) :: :ok | {:error, term()}
end
```

`RawRunResult` is the agent's reported output: messages, tool calls, attempted commands,
final summary, and diff. It is **not** trusted evidence. The conductor turns it into
`Evidence` only after independent verification.

`Conveyor.AgentRunner.Pi` implementation:

1. Materialize the sample repo at `base_commit` into a workspace directory.
2. Create a Docker container from a pinned image containing Pi and the Python toolchain.
3. Mount only the workspace and allowed cache directories.
4. Inject only scoped provider credentials and safe env vars.
5. Launch Pi in RPC/JSON mode over stdin/stdout and connect via a BEAM Port.
6. Stream Pi events into the `Ledger` with heartbeats.
7. Enforce max runtime, max idle time, output size limits, and policy decisions.
8. Collect final diff and reported results.
9. Tear down container unless configured to preserve it for debugging.

Pi remains first because it provides a structured RPC seam and minimal overlap with the
conductor. The adapter contract is deliberately broader than Pi so other agents can be
added without reworking the Slice journey.

---

## 16. Evidence packet, dossier, and PR-body draft

A Slice is not done because an agent says it is done. It is done when the conductor has a
complete evidence packet and the gate passes.

### 16.1 Machine evidence schema

```json
{
  "run_id": "run_123",
  "slice_id": "slice_123",
  "agent": {"adapter": "pi", "model": "...", "profile": "implementer"},
  "base_commit": "abc123",
  "head_commit": "def456",
  "autonomy_level": "L1",
  "summary": "Added PATCH /tasks/{id} completion behavior",
  "changed_files": ["app/main.py", "tests/test_tasks.py"],
  "diff_ref": "diff.patch",
  "commands_run": [
    {"command": "pytest -q", "required": true, "exit_code": 0, "duration_seconds": 1.38}
  ],
  "acceptance_criteria": [
    {
      "id": "ac-001",
      "criterion": "PATCH /tasks/{id} with completed=true returns 200",
      "status": "passed",
      "evidence": ["tests/test_tasks.py::test_complete_task"]
    }
  ],
  "codescent": {
    "baseline_ref": "codescent/before.json",
    "after_ref": "codescent/after.json",
    "new_high_risk_findings": 0
  },
  "policy": {"profile": "implement", "violations": []},
  "review": {"decision": "accepted", "recommendation": "merge"},
  "gate": {"passed": true, "stages": []},
  "known_risks": []
}
```

### 16.2 Human dossier

`dossier.md` should be readable without opening the database:

```markdown
# Run Dossier: run_123

## Slice

## Requirement Traceability

## Summary

## Diff

## Acceptance Criteria → Evidence

## Commands Re-run by Conductor

## CodeScent Delta

## Reviewer Verdict

## Gate Result

## Policy / Safety

## Known Risks

## Retrospective Notes
```

### 16.3 PR-body draft

Even though Phase 1 merge is manual and no PR is opened, `pr_body.md` is generated. This
forces evidence quality to match the later L2 promise.

```markdown
## Task
Implements Slice `<id>` from requirement(s) `<REQ-...>`.

## Summary

## Acceptance Criteria
- [x] ...

## Verification
- [x] `pytest -q`
- [x] CodeScent: no new high-risk findings
- [x] RunCheck: manifest/dossier valid
- [x] Reviewer: accepted

## Risk

## Agent

## Evidence
```

---

## 17. Deterministic gate

The gate is the heart of the factory. Phase 1 implements a Slice-level gate only, but the
stage model must support later epic/phase gates.

Gate stages:

1. **Workspace integrity:** expected base commit, no forbidden files changed, diff exists.
2. **Policy:** no blocked command classes, no forbidden env/network access, no policy file
   edits.
3. **Build/install:** environment can install and import the app.
4. **Tests:** conductor re-runs required pytest cases and any baseline suite required by
   the Brief.
5. **Acceptance mapping:** every acceptance criterion has passed evidence; none are
   missing/skipped unless explicitly allowed.
6. **CodeScent delta:** no new high-risk findings; configured thresholds respected.
7. **RunCheck:** manifest/dossier/evidence/review/gate artifacts are schema-valid and
   internally consistent.
8. **Reviewer:** separate reviewer returns schema-valid `accepted` or appropriate rework.
9. **Canary health:** latest enabled gate-canary run for the project is green.

All required stages must pass. Any failure records a `GateResult`, creates findings, and
moves the Slice to `needs_rework`, `policy_blocked`, or `failed`.

### Stop-the-line policy

In Phase 1, stop-the-line is local: a critical gate or canary failure prevents merge and
blocks further runs for the sample project until addressed. In future phases it will pause
related conflict domains or the entire swarm when trunk/dev health is compromised.

---

## 18. Gate-canary harness

The riskiest assumption in all of Conveyor is that the verification gate can be trusted.
Validate gate honesty immediately.

Phase-1 canary requirements:

- Maintain a small labeled mutant set for the sample app.
- Each mutant is a patch against the known-good solution with one injected defect.
- Run each mutant through the **gate only**; do not invoke the implementer.
- Assert every mutant fails the gate for the expected reason or an equally valid stricter
  reason.
- Track false negatives: mutants the gate wrongly passes.
- A passed mutant is a release-blocking Conveyor bug and should fail CI.

Initial mutants:

| Mutant | Expected catch |
|---|---|
| `patch_unknown_id_returns_200` | 404 acceptance test fails |
| `completed_not_persisted_to_list` | list reflection test fails |
| `default_completed_missing` | create/list regression test fails |
| `test_weakened_or_deleted` | RunCheck / required test check fails |
| `new_codescent_high_risk` | CodeScent delta stage fails |
| `forbidden_policy_edit` | policy stage fails |

Canary output appears in LiveView and `.conveyor/runs/<run_id>/canary/mutants.json`.

---

## 19. Reviewer-on-dossier

The reviewer is a separate agent role, ideally a different model/profile from the
implementer. It reads only the recorded dossier and artifacts, not the live session. This
makes review reproducible and prevents the reviewer from being swayed by undocumented
agent narration.

Reviewer output schema:

```json
{
  "decision": "accepted | needs_rework | rejected",
  "recommendation": "merge | rework | ask_human | archive",
  "summary": "...",
  "findings": [
    {"severity": "blocking | warning | note", "message": "...", "evidence_ref": "..."}
  ],
  "checks": {
    "acceptance_criteria_mapped": true,
    "tests_adequate": true,
    "diff_scope_reasonable": true,
    "no_obvious_policy_issue": true
  }
}
```

Ash policies enforce reviewer actor/profile ≠ implementer actor/profile. Malformed
reviewer output fails the gate; it does not get interpreted creatively.

---

## 20. Failure taxonomy and rework loop

Every failed run should teach which station needs improvement. "Agent failed" is too
vague.

Failure categories:

| Category | Meaning | Typical fix |
|---|---|---|
| Brief Failure | Contract vague, too large, contradictory, missing ACs | Rewrite/split Brief; add decisions |
| Plan Audit Failure | Requirements or decisions not handoff-ready | Clarify plan; add traceability |
| Context-Pack Miss | Scout omitted critical files/interfaces/tests | Improve scout/CodeScent queries |
| Execution Failure | Implementer could not produce a valid diff | Retry with better prompt or park |
| Validation Failure | Tests/build/CodeScent/RunCheck failed | Rework implementation or tests |
| Review Failure | Reviewer found issues despite green deterministic checks | Rework; improve gate if reviewer is right |
| Policy Failure | Dangerous command/env/file behavior attempted | Tighten prompt/policy or park |
| Canary Failure | Gate passed a known-bad mutant | Fix gate before more autonomy |
| Memory Failure | Future: wrong/irrelevant memory caused drift | Adjust memory selection |

Phase 1 does not need autonomous retries, but it must record enough structured data for a
human or future supervisor agent to generate a precise handoff:

```markdown
# Rework Handoff
Previous run:
Failure category:
Blocking finding:
Files changed:
Commands run:
Evidence refs:
Recommended next step:
```

---

## 21. Minimal LiveView and static report

Phase 1 has a small LiveView page plus generated Markdown/JSON reports. Do not overbuild a
beautiful dashboard yet.

LiveView shows:

- Project / Plan / Epic / Slice hierarchy.
- Plan audit score and blocking findings.
- Slice state and full ledger timeline.
- Live agent events and heartbeat.
- Context Pack and relevant files.
- Run Prompt version and policy profile.
- Evidence packet with acceptance criteria → proof mapping.
- CodeScent before/after delta.
- Reviewer verdict and findings.
- Gate stages with pass/fail details.
- Canary status.
- Incidents / policy violations.
- Manual Merge button for Phase 1.

Static report mirrors the above in `.conveyor/runs/<run_id>/dossier.md` so the system stays
useful in headless/CI contexts.

---

## 22. The literal tracer bullet

### 22.1 Sample testbed

A disposable git repo: a tiny FastAPI "tasks" service with `GET /tasks`, `POST /tasks`, an
in-memory or SQLite store, and pytest. It starts from a known base commit.

### 22.2 Phase-1 plan excerpt

```markdown
# Project Goal
Extend the sample tasks API so tasks can be marked complete.

# Non-goals
Authentication, pagination, un-completing a task, bulk updates, deployment.

# Requirement REQ-001
New tasks expose `completed: false` by default.

# Requirement REQ-002
A client can mark an existing task complete through `PATCH /tasks/{id}`.

# Requirement REQ-003
Completed state is returned by `GET /tasks`.

# Requirement REQ-004
Patching an unknown task id returns 404.

# Test Strategy
Human-authored pytest cases cover REQ-001..REQ-004 before the implementer runs.

# Verification Commands
`pytest -q`
```

### 22.3 First Slice Agent Brief

```markdown
## Agent Brief — Add "complete a task" endpoint

Category: enhancement   Risk: low   Autonomy ceiling: L1

Source requirements:
- REQ-001 New tasks expose `completed: false` by default.
- REQ-002 A client can mark an existing task complete through `PATCH /tasks/{id}`.
- REQ-003 Completed state is returned by `GET /tasks`.
- REQ-004 Patching an unknown task id returns 404.

Current behavior: Tasks can be created and listed. There is no way to mark a task complete.

Desired behavior: A client can mark a task complete; completed state is persisted and
returned by the list endpoint. Marking a non-existent task returns 404.

Key interfaces:
- HTTP: `PATCH /tasks/{id}` with body `{"completed": true}` → 200 with the updated task.
- The task representation gains a boolean `completed` field (default false).
- `PATCH` on an unknown id → 404 with a clear error body.

Acceptance criteria:
- [ ] AC-001: New tasks include `completed: false`.
- [ ] AC-002: `PATCH /tasks/{id}` with `{"completed": true}` returns 200 and the task with
      `completed: true`.
- [ ] AC-003: The completed state is reflected in `GET /tasks`.
- [ ] AC-004: `PATCH` on a non-existent id returns 404.
- [ ] AC-005: Existing create/list behavior is unchanged.

Required tests:
- `tests/test_tasks.py::test_create_defaults_completed_false`
- `tests/test_tasks.py::test_complete_task`
- `tests/test_tasks.py::test_completed_state_visible_in_list`
- `tests/test_tasks.py::test_complete_unknown_task_returns_404`
- existing create/list regression tests

Verification commands:
- `pytest -q`

Out of scope:
- Authentication, pagination, un-completing a task, bulk updates, deployment.
```

The human acts as Test Architect in Phase 1 and commits failing pytest cases before the
implementer runs. The implementer cannot weaken those tests; the conductor checks the
required test refs and re-runs them independently.

### 22.4 Station-by-station

1. **Initialize** — `mix conveyor.init` creates `.conveyor/`, config, policies, starter
   `AGENTS.md`, and artifact directories.
2. **Doctor** — `mix conveyor.doctor` verifies Docker, Pi, CodeScent, Postgres, project
   commands, policy, and sample repo cleanliness.
3. **Seed** — `mix conveyor.seed_sample` creates Project → Plan → Requirement → Epic →
   Slice → AgentBrief and records the base commit.
4. **Plan audit** — `PlanAudit` validates required sections, requirement coverage,
   required tests, verification commands, risk policy, and traceability → `handoff_ready`.
5. **Readiness** — `Readiness.check/1` confirms Brief lock, concrete ACs, required tests,
   key interfaces, out-of-scope, and risk → `ready`.
6. **Scout** — `ContextScout` scans repo and CodeScent, producing a cited `ContextPack` →
   `scouted`.
7. **Prompt** — `PromptBuilder` emits a versioned prompt containing Brief, Pack,
   AGENTS.md, policy, and output schema → `prompt_built`.
8. **Implement** — `AgentRunner.Pi` runs inside Docker under `implement` policy; events
   stream to the ledger; final diff is captured → `implementing`.
9. **Record evidence** — `EvidenceRecorder` independently re-runs pytest + CodeScent in a
   clean gate environment, maps ACs to results, writes manifest/dossier/evidence/diff,
   and validates idempotency → `evidence_recorded`.
10. **Review** — separate reviewer profile reads the recorded dossier and returns a
    structured verdict → `reviewed`.
11. **Gate** — deterministic gate composes policy, build, tests, acceptance mapping,
    CodeScent delta, RunCheck, reviewer, and canary health → `gated` if all pass.
12. **Report** — artifact projector writes `.conveyor/runs/<run_id>/` and PR-body draft.
13. **Merge** — human inspects LiveView/dossier and clicks Merge → `integrated` → `done`.
14. **Retrospective** — run records failure taxonomy, timings, prompt version, adapter
    friction, and lessons for Phase 2/3.

---

## 23. Testing strategy for Conveyor itself

- **TDD the deterministic core.** `Readiness`, `PlanAudit`, `Traceability`,
  `PromptBuilder`, `RunCheck`, `EvidenceRecorder`, `Gate`, `Policy.Engine`, and artifact
  projection receive the most ExUnit coverage.
- **Fake `AgentRunner` by default.** Unit/integration tests use a deterministic fake
  implementer/reviewer returning canned results. No live model calls in default CI.
- **Live Pi behind tagged tests.** `@tag :live_agent` runs only on demand.
- **State-machine tests.** Legal transitions succeed, illegal ones fail, guards are
  enforced, and each transition writes exactly one ledger event.
- **Plan audit snapshot tests.** Good plan passes; vague/missing/untraceable plans fail
  with stable findings.
- **AGENTS.md linter tests.** Missing commands, vague done criteria, contradictory policy,
  and missing security rules are caught.
- **Policy tests.** Dangerous command examples create incidents and block runs.
- **Evidence idempotency tests.** Regenerating artifacts from the same records preserves
  checksums or updates only expected timestamps.
- **RunCheck malformed artifact tests.** Missing refs, mismatched manifests, invalid enum
  values, and absent AC evidence fail.
- **Gate-canary tests.** Every enabled mutant is rejected; a false negative fails CI.
- **Clean-container reproducibility test.** A diff that passes in the agent container must
  pass in the gate container, or the run fails.

---

## 24. Risks & open questions

| Risk / question | Phase 0/1 stance |
|---|---|
| Gate trustworthiness | Front-load via canary false-negative measurement; a passed mutant blocks release. |
| Scope creep | Factory kernel only: conductor, evidence, policy, audit, adapter. No issue tracker/chat/deploy platform. |
| Pi RPC maturity / protocol churn | Contained behind `AgentRunner`; use fake runner in default suite; keep Codex/Claude adapter seam ready. |
| Docker latency | Acceptable for one Slice; record timings for future pooling/warm-container decisions. |
| Docker false sense of safety | Add explicit `ExecPolicy`, env allowlist, denylist, incident log, and no production secrets. |
| Flaky tests corrupting evidence | Conductor re-runs cleanly; flakes become validation noise to fix before scaling. |
| Plan audit overfitting | Start deterministic and simple; false positives are acceptable if findings are actionable. |
| Ash learning curve / schema churn | Keep resource APIs stable; write migrations/tests early; mark future-only resources as stubs. |
| Artifact truth split | Postgres is truth; disk artifacts are regenerated projections with checksums. |
| Context Scout too weak | Phase 1 mostly deterministic; measure context-pack miss rate before investing in agentic scout. |
| CodeScent treated as proof | Explicitly only a risk/context/gate-delta signal; tests and RunCheck remain required. |
| Reviewer rubber-stamping | Separate profile/model where possible; schema validation; reviewer findings tracked against later bugs. |
| AGENTS.md drift | Linter compares file against project config and policy. |
| Autonomy expectations | Phase 1 states L1 with L2 artifacts; no auto-merge/deploy. |

---

## 25. Milestone / task breakdown with acceptance criteria

### Phase 0 — Foundations and factory kernel

- **P0.0 Product contract docs.** Create `VISION.md`, `AUTONOMY_LEVELS.md`,
  `SAFETY_POLICY.md`, `TASK_SCHEMA.md`, `EVIDENCE_SCHEMA.md`, and `ARCHITECTURE.md`.
  *AC:* docs state L1 Phase-1 target, evidence requirements, policy defaults, and
  non-goals.
- **P0.1 Project scaffold.** Phoenix+Ash+Oban+Postgres app boots; CI runs `mix test`,
  `mix format --check-formatted`, Credo/Dialyzer if configured. *AC:* app boots and CI is
  green.
- **P0.2 Config + doctor.** `.conveyor/config.toml` plus `mix conveyor.doctor`. *AC:*
  missing Docker/Pi/CodeScent/Postgres/test commands/policies are reported clearly.
- **P0.3 Ash domain & migrations.** Active resources in §6.1 are defined; stub resources
  in §6.2 exist where useful. *AC:* migrations apply; resources create/read/update through
  Ash.
- **P0.4 Plan audit + traceability.** Implement `Requirement`, `HumanDecision`,
  `PlanAudit`, scoring, and deterministic findings. *AC:* good sample plan is
  `handoff_ready`; vague sample plan is blocked.
- **P0.5 Slice state machine + ledger.** Implement §7 transitions and append-only
  `LedgerEvent`. *AC:* legal transitions succeed, illegal transitions fail, event replay
  reconstructs state.
- **P0.6 Policy engine.** Implement profiles, denylist/allowlist checks, env policy, and
  incidents. *AC:* dangerous command fixtures are blocked and recorded.
- **P0.7 AGENTS.md generator/linter.** Generate starter file and lint for required
  commands/rules. *AC:* generated file passes; intentionally incomplete file fails with
  useful findings.
- **P0.8 Artifact projector.** Create `.conveyor/runs/<run_id>/` projection code. *AC:*
  manifest/dossier/evidence paths regenerate idempotently from database records.
- **P0.9 LiveView skeleton.** Run viewer renders Project/Plan/Slice state and ledger
  timeline. *AC:* seeded Slice updates live when ledger events append.

### Phase 1 — Single-Slice tracer bullet

- **P1.1 Sample app + base commit.** FastAPI tasks repo with existing create/list behavior
  and pytest. *AC:* baseline tests pass at known commit.
- **P1.2 Human-authored plan, Brief, and failing tests.** Add Phase-1 plan, requirements,
  first Slice, Agent Brief, and failing pytest cases. *AC:* new tests fail before
  implementation; existing tests pass.
- **P1.3 Plan audit gate.** Run `mix conveyor.plan_audit`. *AC:* sample plan reaches
  `handoff_ready`; missing AC/test/decision fixtures fail.
- **P1.4 Readiness gate.** Validate locked Brief. *AC:* complete Brief → `ready`; vague or
  testless Brief → `needs_clarification`/`too_large`.
- **P1.5 Context Scout + CodeScent baseline.** Produce cited `ContextPack` and baseline
  CodeScent artifact. *AC:* pack names router/model/tests with reasons and confidence.
- **P1.6 Prompt builder.** Versioned prompt includes Brief, Pack, AGENTS.md, policy,
  required tests, and output schema. *AC:* snapshot-tested; no unlocked fields omitted.
- **P1.7 Docker workspace + policy enforcement.** Materialize repo in container and enforce
  implement profile. *AC:* allowed commands run; forbidden fixtures create incidents.
- **P1.8 Pi AgentRunner over RPC.** Given a RunPrompt, Pi edits the repo and returns a
  `RawRunResult`. *AC:* events stream to ledger; final diff is captured; timeouts/idle
  detection work.
- **P1.9 Evidence recorder + independent verification.** Re-run pytest + CodeScent in a
  clean gate environment. *AC:* writes evidence/dossier/manifest/diff/logs; maps ACs;
  rejects missing required tests; regeneration is idempotent.
- **P1.10 Reviewer-on-dossier.** Separate reviewer profile returns structured `Review`.
  *AC:* malformed review is rejected; reviewer actor/profile ≠ implementer.
- **P1.11 Deterministic gate.** Compose all gate stages. *AC:* gate passes only if every
  required stage passes; each failing fixture blocks at the expected stage.
- **P1.12 Gate-canary harness.** Run enabled mutant set through gate-only path. *AC:* every
  mutant is rejected; false-negative rate is reported; any passed mutant fails CI.
- **P1.13 LiveView + static report complete.** Show timeline, audit, context, agent stream,
  evidence, review, gate, canary, incidents, and Merge button; write `pr_body.md`. *AC:*
  dossier is usable without LiveView.
- **P1.14 End-to-end tracer run.** One human action drives approved Slice to `gated`; human
  merges manually to `done`. *AC:* run replays from event log and artifacts regenerate.
- **P1.15 Retrospective record.** Capture timings, token/cost estimate if available,
  adapter friction, failure taxonomy, gate-canary stats, and schema friction. *AC:* report
  states whether Phase 2/3 assumptions still hold.

---

## 26. Deferred roadmap hooks deliberately seeded by Phase 0/1

Do not build these now, but keep the data model and evidence fields ready.

### Phase 2 — Decomposition + approval gate

- Spec agent converts a handoff-ready plan into Epics/Slices/Briefs.
- Critic agent audits contracts.
- Human approves/tweaks Slice breakdown before execution.
- Plan compiler graduates from audit to generation, but audit remains the gate.

### Phase 3 — Parallel fleet + merge queue

- Dispatcher selects ready Slices.
- WorkerPool runs isolated containers concurrently.
- MergeQueue integrates into `dev`, then phase gate promotes to `main`.
- Conflict domains and likely files feed scheduling.

### Phase 4 — Verification pyramid

- Slice gate stays fast.
- Epic gate adds integration/e2e, property tests, mutation tests, and adversarial
  red-team review.
- Phase gate adds full regression, dependency/security audit, and human digest.

### Phase 5 — Autonomy + self-healing

- Watchdog detects silence, loops, repeated failures, or no git/gate progress.
- Retry budgets escalate to supervisor agent, re-plan, park, or stop-the-line.
- Autonomy level rises only after measured gate reliability.

### Phase 6 — Economic governor + observability

- Cost ledger, budget caps, rate-limit-aware credentials, runaway kill-switch.
- LiveView adds cost meters, critical path, and parked queue.

### Phase 7 — Learning loop

- Structured memory and pgvector recall.
- Prompt template optimization based on first-pass success, rework rounds,
  context-pack misses, review rejection, and cost per success.
- Factory retrospective proposes AGENTS.md, policy, plan-template, and prompt-template
  updates.

### Phase 8 — Throughput upgrades

- Interface-stub parallelism.
- Swarm dry-run simulator.
- Agent reputation routing.
- Conflict heatmap.
- BEAM distribution for horizontal scale.
- Optional adapters to Beads, GitHub Issues, Linear, OpenHands, Claude Code, Codex,
  OpenCode, Aider, Goose, and other agents/tools.

---

## 27. Swarm-readiness fields to capture now

Phase 1 is single-run, but each run should record the future scheduling/evaluation data:

```text
likely_files
conflict_domains
risk
autonomy_ceiling
agent adapter/profile/model
prompt template version
context scout version
reviewer profile/model
commands attempted
commands independently verified
gate stages and failures
canary false-negative rate
policy incidents
time to first diff
time to green
rework category
cost/tokens if available
files changed count
lines changed count
review decision
human merge decision
post-merge notes
```

These are the seeds of the later swarm simulator, scheduler score, conflict heatmap,
agent reputation, and economic governor. Capturing them now costs little; inventing them
after dozens of runs would lose the eval dataset.

---

## 28. What success in Phase 1 teaches us

Phase 1 is successful only if it answers these questions with evidence:

- Does the loop feel right on a real change?
- Can plan audit distinguish executable handoff from vague prose?
- Can the gate reject labeled bad changes with zero false negatives on the initial mutant
  set?
- Is the Pi/RPC seam clean enough to keep, or should the next adapter be prioritized?
- Are the Ash schemas stable under a real run?
- Does `AGENTS.md` reduce prompt ambiguity?
- Does CodeScent provide useful scout/gate signals without being mistaken for proof?
- Are artifacts reviewable enough to support an eventual PR-generation workflow?
- Did policy block anything useful or miss anything dangerous?
- What is the minimum next step: better plan compiler, better gate, better adapter, or
  parallelism?

Only once the gate proves honest and the single-Slice loop proves real do we earn Phase
3's parallelism. More agents before trust would only make the system faster at producing
untrusted diffs.
