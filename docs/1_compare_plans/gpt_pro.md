My strong take: **build a small “factory kernel,” not a giant autonomous-agent
platform.** The Flywheel stack has many good primitives, but the danger is
copying the whole cathedral before you know which pieces actually matter. Your
first open-source win should be a simple, composable control plane that lets you
safely run multiple coding agents against a dependency-aware task graph, with
durable evidence, safety gates, and human-readable planning artifacts.

The core philosophy I’d use is:

> **The human owns intent, taste, architecture, and acceptance criteria. The
> factory owns coordination, safety, memory, and verification. The agents own
> execution of bounded tasks.**

That separation is the difference between a useful software factory and a chaos
machine that produces mysterious diffs at 3 a.m.

---

## 1. What I think you are really building

You are not primarily building “an AI that writes code.”

Claude Code, Codex, OpenCode, Aider, Goose, OpenHands, and others already do
that. Claude Code can read/edit code, run commands, and connect to tools through
MCP; Codex CLI can run locally in the terminal, read and modify code, and
execute commands; OpenHands is an open-source agent platform that can run
locally or at scale, with Docker/Kubernetes-style isolation. ([Claude API
Docs][1])

You are building the missing middle layer:

**A local-first autonomous software production system that turns a
human-authored plan into many safe, trackable, parallel streams of
implementation work.**

That system needs to answer these questions continuously:

1. What should be worked on next?
2. Who or what is working on it?
3. What context does the agent need?
4. What files or areas are likely to conflict?
5. What counts as done?
6. What evidence proves it is done?
7. What should happen when an agent gets stuck?
8. What should never be allowed automatically?
9. What has the factory learned that should improve the next run?

The actual LLM coding agents become interchangeable workers.

That should be one of your strongest design principles.

---

## 2. My pushback on “fully autonomous 24/7”

I agree with the ambition, but I would split “autonomous” into levels.

The dangerous version is:

> “Agents run 24/7, modify code, merge, deploy, and keep going.”

The better version is:

> “Agents run 24/7 generating verified work packets, but merge/deploy authority
> increases only as trust and evidence accumulate.”

I would define autonomy levels from the beginning:

| Level | Name                 | What agents can do                                          |
| ----: | -------------------- | ----------------------------------------------------------- |
|    L0 | Planning only        | Convert plans into tasks, risks, dependencies, test plans   |
|    L1 | Local implementation | Produce diffs in isolated workspaces                        |
|    L2 | PR generation        | Open pull requests with evidence packets                    |
|    L3 | Auto-merge low-risk  | Merge only green, low-risk, well-scoped changes             |
|    L4 | Auto-deploy          | Deploy only after strong repo-specific trust is established |

Your MVP should target **L2: autonomous PR generation**, not full autonomous
production deployment.

That is still extremely powerful. It lets your VPS work around the clock while
you remain the editorial/architectural authority.

---

## 3. What to steal from Agent Flywheel

The Flywheel references are valuable because they identify the right
coordination primitives: planning, dependency-aware tasks, agent mail, graph
analysis, safety guards, testing, and deployment workflow. The workflow page
describes a full lifecycle from ideation and planning through task breakdown,
implementation, review, testing, deployment, and maintenance, with agents
communicating through an email-like system and working from a dependency-aware
graph. ([Agent Flywheel][2])

The best Flywheel idea is this:

> **Tasks are not todos. Tasks are executable memory.**

The complete guide argues that tasks need rich context, explicit dependencies,
acceptance criteria, and testing instructions so agents can execute them
independently after compaction, interruption, or handoff. ([Agent Flywheel][3])

That is exactly right.

Where I disagree with Flywheel is operational complexity. The full stack
includes many tools: NTM, Agent Mail, UBS, Beads, Beads Viewer, RCH, CASS, CASS
Memory, CAAM, DCG, SLB, and more. The guide itself describes this as an 11-tool
stack. ([Agent Flywheel][3])

For your project, I would not begin there.

I would collapse the first version into four essentials:

1. **Task graph**
2. **Agent runner**
3. **Verification/evidence gate**
4. **Safety/coordination layer**

Everything else should be optional.

---

## 4. The architecture I recommend

I would design the factory as a set of replaceable layers.

```text
Human Plan
   ↓
Planning Workbench
   ↓
Task Graph / Issue Substrate
   ↓
Factory Control Plane
   ↓
Agent Adapters
   ↓
Isolated Workspaces
   ↓
Verification Gates
   ↓
Review / Merge Queue
   ↓
Learning Memory
```

### Layer 1: Planning workbench

This is where you, the human, do the high-leverage work.

Inputs:

- `PLAN.md`
- `ARCHITECTURE.md`
- `PRODUCT_BRIEF.md`
- `DECISIONS.md`
- `AGENTS.md`
- repo conventions
- non-goals
- acceptance criteria
- risk constraints

The factory should not assume that “planning” is just issue generation. Planning
is where ambiguity gets killed.

A good plan should include:

```markdown
# Project Goal

# Non-goals

# User Stories

# Technical Architecture

# Constraints

# Risk Areas

# Milestones

# Acceptance Criteria

# Test Strategy

# Deployment Strategy

# Open Questions

# Explicit Human Decisions
```

Then the factory converts this into tasks.

The key is round-tripping:

> Every important requirement in the plan should map to one or more tasks. Every
> task should map back to a requirement, decision, bug, or improvement.

This prevents agents from creating plausible but irrelevant work.

This should become one of your killer features: **plan-to-task traceability**.

---

### Layer 2: Task graph

You should not build a full issue tracker from scratch.

Use Beads or a Beads-compatible abstraction.

There are two relevant Beads paths:

The current GasTown/Steve Yegge Beads project uses `bd`, Dolt, dependency
tracking, JSON output, hierarchical IDs, messaging, graph links, and an
agent-oriented workflow. ([GitHub][4])

The Agent Flywheel ecosystem uses the Rust `br` fork, which explicitly preserves
the older SQLite + JSONL architecture, with local-first issue tracking,
dependency-aware tasks, `br ready`, `br coordination status`, explicit sync, and
agent-friendly JSON output. ([GitHub][5])

My recommendation:

**Start with `br` if your first goal is compatibility with the Flywheel-style
local-first workflow. Design an adapter so you can support `bd`, GitHub Issues,
Linear, or Jira later.**

Do not hard-code your factory around one issue tool.

Use an interface like:

```ts
interface TaskGraph {
  listReadyTasks(): Task[];
  getTask(id: string): Task;
  claimTask(id: string, agentId: string): Claim;
  updateTask(id: string, patch: TaskUpdate): void;
  blockTask(id: string, reason: string): void;
  closeTask(id: string, evidence: EvidencePacket): void;
  listDependencies(id: string): Task[];
  exportGraph(): DependencyGraph;
}
```

Then `br`, `bd`, GitHub Issues, and other systems become plugins.

---

### Layer 3: Factory control plane

This is the part you probably do need to build.

Call it something like:

- `factoryd`
- `forge`
- `swarmd`
- `autofactory`
- `code-factory`

Its job is not to be smart. Its job is to be strict.

It should maintain:

- agent sessions
- task claims
- workspace assignments
- budgets
- file reservations
- run logs
- verification evidence
- failure reasons
- stale work detection
- blocked task state
- conflict state
- merge queue state

The first version can just use SQLite.

Suggested internal tables:

```text
projects
agent_sessions
task_claims
workspaces
file_reservations
run_events
verification_runs
evidence_packets
review_requests
merge_queue
incidents
budgets
factory_settings
```

Important: I would not make the control plane the source of truth for tasks. Let
Beads/`br`/`bd` be the task source of truth. Let Agent Mail be the communication
source of truth. Let Git be the code source of truth.

The factory database should be the **event ledger and orchestration state**, not
the universe.

---

### Layer 4: Agent adapters

The factory should treat coding agents as interchangeable executors.

Initial adapters:

- Claude Code
- OpenAI Codex CLI
- maybe OpenCode
- maybe Aider
- maybe Goose
- later OpenHands for heavier sandboxed scaling

Claude Code has non-interactive and automation-oriented CLI modes, flags for
background work, permission modes, budgets, max turns, JSON schema output,
allowed/disallowed tools, and MCP configuration. ([Claude API Docs][6])

Codex CLI is OpenAI’s local terminal coding agent; it can read, modify, and run
code locally, and it is open source. ([OpenAI Developers][7])

OpenCode is also relevant because it supports terminal/IDE/desktop usage,
multiple parallel sessions, multiple providers, and ChatGPT Plus/Pro
authentication. ([OpenCode][8])

Aider is useful for repo-map-heavy terminal coding with Git integration and
auto-commits. ([GitHub][9])

Goose is worth watching because it supports desktop, CLI, API, MCP extensions,
recipes, multiple providers, and subagents. ([Goose Docs][10])

Your adapter contract should be simple:

```ts
interface AgentAdapter {
  name: string;
  capabilities: AgentCapabilities;

  startSession(input: AgentRunInput): AgentSession;
  streamEvents(sessionId: string): AsyncIterable<AgentEvent>;
  cancel(sessionId: string): void;
  collectResult(sessionId: string): AgentRunResult;
}
```

Each agent run should receive the same structured prompt envelope.

Example:

```markdown
You are worker {{agent_id}} in project {{project_name}}.

Read first:

1. AGENTS.md
2. The assigned task
3. Related dependencies
4. Relevant architecture docs
5. Existing tests

Task: {{task_body}}

Rules:

- Claim the task before editing.
- Reserve files before editing.
- Keep the change small.
- Do not modify unrelated files.
- Do not close the task unless acceptance criteria are met.
- Run the required verification commands.
- Record evidence.
- If blocked, write a blocker note and stop.

Required output:

- Summary of changes
- Files changed
- Tests run
- Evidence
- Remaining risks
```

The important thing is that every agent receives a **bounded contract**, not a
vague instruction like “go build this feature.”

---

### Layer 5: Agent-readable project instructions

Use `AGENTS.md`.

The AGENTS.md format is intentionally a simple open convention: a predictable
file for coding agents, analogous to README files for humans. It is meant to
document project overview, build/test commands, style rules, testing
instructions, security notes, and PR expectations. ([Agents][11])

Your factory should generate and maintain this file.

A factory-generated `AGENTS.md` should include:

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

# How to Use Beads

# How to Use Agent Mail

# How to Use CodeScent

# How to Report Blockers
```

One of your best design opportunities is an **AGENTS.md linter**.

It should detect missing commands, vague done criteria, missing security rules,
and instructions that contradict the actual repo.

---

### Layer 6: Coordination and communication

Do not build chat from scratch.

Use Agent Mail or something very close to it.

MCP Agent Mail provides an email-like coordination layer for coding agents,
including identities, inbox/outbox, searchable message history, and voluntary
file reservation leases, backed by SQLite/Git. ([GitHub][12])

This is exactly the right primitive.

But I would impose discipline:

Agent communication should be mostly structured.

Message types:

```text
QUESTION
ANSWER
BLOCKER
HANDOFF
REVIEW_REQUEST
REVIEW_RESULT
FILE_RESERVATION
CONFLICT_WARNING
DECISION_NEEDED
TASK_SPLIT_REQUEST
```

You do not want ten agents casually chatting. You want them emitting durable
coordination artifacts.

The factory should summarize important Agent Mail threads back into the task
record.

---

### Layer 7: Code intelligence

This is where `code-scent-mcp` fits beautifully.

CodeScent is a local MCP-first codebase improvement server. It indexes
repositories locally, stores state under `.codescent`, offers deterministic
code-health tooling, and is source-read-only: it writes only its own
`.codescent` state, does not edit source files, and does not use runtime network
access. ([GitHub][13])

Its MCP tools include repo mapping, status, search, symbol finding, code-health
scans, smell reports, next-improvement recommendations, refactor planning, test
suggestions, and risk tools. ([GitHub][14])

That means CodeScent should be used in three places:

#### Before work

Ask:

- What area of the repo is relevant?
- What smells or risks already exist nearby?
- What tests should likely be added?
- What files are risky to modify?

#### During work

Agents can ask:

- Where is this symbol?
- What related files exist?
- What does the local architecture look like?
- What is a safe refactor plan?

#### After work

The factory should ask:

- Did this change introduce new risks?
- Are there unverified recommendations?
- Are tests suggested but missing?
- Is this task safe enough for review?

But CodeScent’s own docs are clear that recommendations are not proof and that
it does not execute tests. ([GitHub][15])

So your factory still needs to run the actual verification commands.

---

### Layer 8: Safety layer

Use Destructive Command Guard or a similar wrapper from day one.

DCG is designed to block destructive commands before execution across coding
agents such as Claude, Codex, Gemini, and others. Its examples include guarding
against things like destructive Git commands, filesystem deletion, and database
destruction. ([GitHub][16])

This should be non-negotiable.

Minimum guardrails:

```text
No rm -rf outside workspace
No git reset --hard without explicit permission
No git clean -fd without explicit permission
No force push
No secret exfiltration
No production database access
No deploy command unless autonomy level allows it
No modifying factory config from inside worker task
No installing global packages without approval
No network calls except allowlisted package registries/APIs
```

The safety layer should have policy profiles:

```text
explore
implement
verify
release
dangerous-maintenance
```

Most agents should run in `implement`.

Very few tasks should ever receive `release`.

---

### Layer 9: Workspace isolation

This is one of the places I disagree with the Flywheel default.

The Flywheel guide argues for a single-branch model where all agents commit to
main, with file reservations and pre-commit guards. ([Agent Flywheel][3])

I understand why: it reduces branch management overhead and keeps everyone in
one shared state.

But I would not make that your default.

For a personal experimental repo, shared-main can be fast.

For an open-source project you want others to trust, I would default to:

```text
one task → one worktree → one branch → one PR/evidence packet → merge queue
```

Then optionally support:

```text
--mode shared-checkout
```

for users who want the Flywheel-style workflow.

My recommendation:

| Mode                    | Best for                                          | Risk                            |
| ----------------------- | ------------------------------------------------- | ------------------------------- |
| Shared checkout         | throwaway prototypes, solo local experiments      | high conflict/blast radius      |
| Git worktree per task   | normal development                                | moderate complexity, much safer |
| Container per task      | untrusted code, high-risk automation, many agents | more infra overhead             |
| Remote sandbox per task | larger scale, paid infra                          | more moving parts               |

For your first public version, use Git worktrees.

Containers can come later.

---

### Layer 10: Verification and evidence

This is the heart of the factory.

An agent should not be allowed to mark a task done by saying “done.”

It should produce an **evidence packet**.

Example evidence packet:

```json
{
  "task_id": "auth-123",
  "agent_id": "claude-3",
  "commit": "abc123",
  "summary": "Added password reset token expiry validation",
  "files_changed": ["src/auth/reset.ts", "tests/auth/reset.test.ts"],
  "commands_run": [
    {
      "command": "npm test -- tests/auth/reset.test.ts",
      "exit_code": 0,
      "duration_seconds": 8.2
    },
    {
      "command": "npm run typecheck",
      "exit_code": 0,
      "duration_seconds": 12.4
    }
  ],
  "codescent": {
    "scan_completed": true,
    "new_high_risk_findings": 0
  },
  "acceptance_criteria": [
    {
      "criterion": "Expired tokens are rejected",
      "status": "passed",
      "evidence": "reset.test.ts includes expired token case"
    }
  ],
  "known_risks": [],
  "review_required": true
}
```

This evidence packet becomes the unit of trust.

Your dashboard should show tasks as:

```text
Not started
Claimed
Working
Blocked
Needs verification
Verification failed
Needs review
Ready to merge
Merged
Released
```

Not simply open/closed.

---

## 5. The dependency and scheduling model

You should combine Beads’ ready-task concept with graph analytics.

The Flywheel ecosystem’s `bv` tool treats the project as a task DAG and computes
metrics like PageRank, betweenness, HITS, critical path, cycle detection, and
topological ordering. ([GitHub][17])

That is useful, but the factory should turn it into an assignment algorithm.

A simple scoring model:

```text
score(task) =
  priority
+ critical_path_weight
+ dependency_unblocking_weight
+ age_weight
- file_conflict_penalty
- risk_penalty
- agent_unsuitability_penalty
```

The scheduler should prefer tasks that:

1. are unblocked,
2. unblock many other tasks,
3. touch files no one else is touching,
4. match the agent’s strengths,
5. have clear acceptance criteria,
6. are small enough to finish in one run.

It should avoid tasks that:

1. are vague,
2. have unclear tests,
3. touch hot files,
4. depend on pending architecture decisions,
5. require secrets or production access,
6. are too large.

This is another place for a killer feature:

> **Swarm dry run.**

Before launching ten agents, the factory should simulate the run:

```text
Ready tasks: 23
Recommended agents: 5
Expected file conflicts: 2
Critical path bottleneck: auth-007
Tasks too vague: 4
Tasks missing verification commands: 6
Suggested first wave:
  - auth-001
  - ui-004
  - db-002
  - docs-003
  - tests-006
```

This would be immediately valuable.

---

## 6. The “factory kernel” MVP

Here is the smallest version I think is worth building.

### MVP command set

```bash
factory doctor
factory init
factory plan audit PLAN.md
factory plan import PLAN.md
factory graph
factory next
factory spawn --count 3
factory watch
factory verify TASK_ID
factory review TASK_ID
factory reclaim-stale
factory pause
factory resume
```

### `factory doctor`

Checks whether the environment is ready:

```text
git installed
gh installed
br or bd installed
Agent Mail installed
CodeScent MCP installed
DCG installed
Claude Code available
Codex CLI available
AGENTS.md present
test commands known
working tree clean
secrets policy configured
```

### `factory init`

Creates:

```text
.factory/config.toml
.factory/events.sqlite
.factory/prompts/
.factory/policies/
AGENTS.md
PLAN.md
DECISIONS.md
```

Optionally initializes Beads/`br`, Agent Mail, CodeScent, and safety hooks.

### `factory plan audit PLAN.md`

This is a planning quality gate.

It should report:

```text
Missing acceptance criteria
Missing test strategy
Unresolved architecture decisions
Large vague stories
Duplicate requirements
Requirements with no task mapping
Tasks with no requirement mapping
Risky areas without review policy
```

### `factory plan import PLAN.md`

Converts your plan into epics/stories/tasks.

Each task should include:

```yaml
id:
title:
type: feature | bug | refactor | test | docs | infra | research
source_requirement:
priority:
risk:
depends_on:
blocks:
likely_files:
context:
acceptance_criteria:
verification_commands:
out_of_scope:
review_policy:
```

### `factory spawn --count 3`

Starts workers against ready tasks.

The runner should:

1. select ready tasks,
2. assign agents,
3. create worktrees,
4. claim tasks,
5. reserve likely files,
6. launch agent sessions,
7. stream logs,
8. collect results,
9. run verification,
10. produce evidence,
11. request review or mark blocked.

### `factory reclaim-stale`

Finds sessions that are inactive, too old, or looping.

The Flywheel guide identifies common stuck-swarm symptoms: duplicated work,
agents going in circles after compaction, in-progress tasks sitting too long,
contradictory implementations, and strategic drift. ([Agent Flywheel][3])

Your reaper should handle those cases.

When reclaiming a task, it should generate a handoff:

```markdown
# Handoff for TASK_ID

Previous agent: Started: Last activity: Files modified: Current diff summary:
Commands run: Failure/blocker: Recommended next step:
```

Then the next agent starts from a clean summary instead of spelunking through
logs.

---

## 7. Recommended initial stack

My suggested first stack:

```text
OS: Ubuntu VPS
Process control: tmux + systemd
Repo: Git + GitHub
Task graph: br first, bd adapter later
Task graph visualization: bv
Agent communication: MCP Agent Mail
Code intelligence: code-scent-mcp
Safety: DCG
Primary agents: Claude Code + Codex CLI
Optional agents: OpenCode, Aider, Goose
Event ledger: SQLite
Factory CLI/control plane: TypeScript, Python, or Rust
CI: GitHub Actions
Project instructions: AGENTS.md
```

The ACFS repository is useful as inspiration because it bootstraps an Ubuntu VPS
into a development environment, installs coding tools and coordination
utilities, uses a manifest-driven architecture, has installer safety modes, and
includes project scaffolding with Git, Beads, Claude settings, and AGENTS.md.
([GitHub][18])

But I would not make ACFS itself the core of your project.

Treat it as prior art for installation and bootstrapping.

Your project should be the simpler orchestration/control plane above the tools.

---

## 8. The role of MCP

MCP should be a tool boundary, not your whole architecture.

MCP is an open standard for connecting AI applications to external tools,
systems, data, and workflows. ([Model Context Protocol][19])

Use MCP for things agents need to call:

- Agent Mail
- CodeScent
- task graph tools
- maybe repo-search tools
- maybe documentation lookup
- maybe browser/testing tools later

Do not wrap every shell command as MCP.

The factory itself can call tools directly. Agents can use MCP where useful.

A clean split:

```text
Factory control plane:
  Directly manages processes, worktrees, verification, logs, policies.

Agents:
  Use MCP for contextual tools such as CodeScent, Agent Mail, task lookup.
```

This avoids MCP-server sprawl.

---

## 9. How I would incorporate CodeScent specifically

CodeScent should become your “local code reviewer and context scout.”

Add factory commands:

```bash
factory scent scan
factory scent task TASK_ID
factory scent risk TASK_ID
factory scent tests TASK_ID
factory scent evidence TASK_ID
```

Before assigning a task, the factory asks CodeScent:

```text
What symbols/files are relevant?
What risks exist in this area?
What tests should be added?
What refactor hazards exist?
```

After the agent finishes, the factory asks:

```text
Did risk increase?
Are there new smells?
Are there missing tests?
Does this change touch high-risk areas?
```

Because CodeScent is source-read-only and evidence-oriented, it is ideal for
autonomous systems. It can inspect and recommend without itself mutating the
codebase. ([GitHub][13])

That makes it a safer primitive than an agent with full edit rights.

---

## 10. The biggest product opportunity: plan-to-task compiler

This is where I think you can build something better than the Flywheel setup.

Most agent workflows fail before coding starts because the plan is vague.

So build a **plan compiler**.

Input:

```markdown
Build a local-first habit tracking app with auth, sync, analytics, and
mobile-friendly UI...
```

Output:

```text
Epics
Stories
Tasks
Dependencies
Acceptance criteria
Verification commands
Risk flags
Open questions
Suggested first wave
```

But the killer feature is not generation.

The killer feature is **critique**.

The plan compiler should say:

```text
This plan is not ready for autonomous execution.

Problems:
1. Auth provider unspecified.
2. Sync conflict behavior undefined.
3. Analytics privacy rules missing.
4. No test strategy for offline mode.
5. "Mobile-friendly" is not measurable.
6. Deployment target unspecified.
7. 14 tasks are too large for one-agent execution.
```

Then it should propose rewrites.

This aligns perfectly with your intended role: you want to do research,
brainstorming, and planning, then hand off a high-quality plan.

So make the factory opinionated about what “handoff-ready” means.

---

## 11. The second biggest product opportunity: evidence ledger

Every autonomous coding platform needs a trust layer.

Your open-source project could stand out by making evidence first-class.

A task is not “done” until it has:

```text
diff
commit
summary
tests run
test output
lint/typecheck/build status
CodeScent scan result
acceptance criteria mapping
known risks
review status
```

That can be stored as:

```text
.factory/evidence/TASK_ID.json
.factory/evidence/TASK_ID.md
```

And attached to PRs.

A PR body could be generated automatically:

```markdown
## Task

Implements bead `auth-123`.

## Summary

Adds expired-token rejection to password reset flow.

## Acceptance Criteria

- [x] Expired tokens are rejected.
- [x] Valid tokens still work.
- [x] Error message does not leak token validity details.

## Verification

- [x] `npm test -- tests/auth/reset.test.ts`
- [x] `npm run typecheck`
- [x] `factory scent risk auth-123`

## Risk

Low. Touches auth reset flow only.

## Agent

claude-3 / session 2026-06-15T...
```

This makes autonomous work reviewable.

That is how you earn trust.

---

## 12. The third biggest product opportunity: swarm simulator

Before starting ten agents, the factory should tell you whether ten agents make
sense.

Example:

```bash
factory simulate --agents 10
```

Output:

```text
Recommended: 4 agents, not 10.

Why:
- Only 6 tasks are currently unblocked.
- 3 tasks touch src/auth/session.ts.
- 2 tasks require the database schema task to land first.
- 4 tasks are missing verification commands.
- Critical path starts with db-001.

Suggested launch:
1. db-001       agent: Claude Code   risk: medium
2. ui-004       agent: Codex         risk: low
3. docs-002     agent: Codex         risk: low
4. tests-003    agent: Claude Code   risk: low
```

This is the kind of “factory manager” intelligence that normal coding agents
lack.

It also prevents the seductive mistake of thinking more agents always means more
progress.

Often, five good agents beat twenty chaotic ones.

---

## 13. The fourth biggest product opportunity: agent reputation

Track which agents are good at which work.

Metrics:

```text
task type
language/framework
success rate
verification pass rate
average retries
review rejection rate
bug introduction rate
cost
duration
files touched
rollback rate
```

Then route tasks intelligently:

```text
Claude Code:
  strong: architecture refactors, test generation, reasoning-heavy changes
  weak: repetitive mechanical edits? maybe not, depends on observed data

Codex:
  strong: terminal-native code modifications, smaller scoped tasks
  weak: depends on model/config

Aider:
  strong: repo-map-guided pair programming, focused Git diffs

OpenHands:
  strong: sandboxed long-running tasks, scaled execution
```

Do not hard-code these assumptions. Measure them.

The factory should learn from its own runs.

---

## 14. What I would not build initially

I would explicitly avoid these in v0:

1. **A new issue tracker**

   Use Beads/`br`/`bd`.

2. **A new chat system**

   Use Agent Mail.

3. **A new static analyzer**

   Use CodeScent, tree-sitter, ripgrep, language servers, existing linters.

4. **A custom LLM framework**

   Wrap existing CLIs first.

5. **Auto-deploy**

   Generate PRs before generating production changes.

6. **Multi-repo orchestration**

   Start with one repo.

7. **Ten-agent concurrency**

   Start with two or three. Add concurrency after you have evidence gates.

8. **A beautiful web dashboard**

   Start with a terminal dashboard and Markdown/JSON artifacts.

9. **Complex memory/RAG**

   Start with durable files: tasks, decisions, evidence, mail, commits.

10. **Fine-tuning**

Not needed. Better prompts, smaller tasks, and better evidence will matter more.

---

## 15. My proposed implementation plan

### Phase 0: Design constraints

Define the product contract.

Deliverables:

```text
VISION.md
NON_GOALS.md
ARCHITECTURE.md
AUTONOMY_LEVELS.md
SAFETY_POLICY.md
TASK_SCHEMA.md
EVIDENCE_SCHEMA.md
```

Key decision:

> The first public version is a supervised autonomous PR factory, not a fully
> autonomous deployer.

---

### Phase 1: Bootstrap a repo

Build:

```bash
factory init
factory doctor
```

`factory init` creates:

```text
.factory/
  config.toml
  events.sqlite
  prompts/
  policies/
  evidence/
  logs/
AGENTS.md
PLAN.md
DECISIONS.md
```

`factory doctor` checks:

```text
git
gh
br/bd
CodeScent
Agent Mail
DCG
Claude Code
Codex
test commands
clean working tree
```

Acceptance criteria:

```text
A fresh repo can be initialized.
Missing tools are reported clearly.
AGENTS.md is generated.
Factory config is valid.
```

---

### Phase 2: Task graph adapter

Build a `TaskGraph` interface with one concrete implementation first.

I would start with `br`.

Commands:

```bash
factory graph
factory next
factory task show TASK_ID
factory task claim TASK_ID
factory task block TASK_ID
```

Acceptance criteria:

```text
Factory can list ready tasks.
Factory can claim a task.
Factory can detect blocked tasks.
Factory can read dependencies.
Factory can emit graph summary JSON.
```

---

### Phase 3: Plan compiler

Build:

```bash
factory plan audit PLAN.md
factory plan import PLAN.md
```

This should initially be semi-automated. Let an LLM propose tasks, but require a
human review before writing them.

Audit checks:

```text
missing acceptance criteria
missing test commands
oversized tasks
unclear dependencies
undefined terms
open architecture decisions
requirements without task coverage
tasks without requirement source
```

Acceptance criteria:

```text
Given PLAN.md, factory proposes epics/stories/tasks.
Every task has acceptance criteria.
Every task has a source requirement.
Every task has a verification plan or is flagged.
Human can accept/edit before import.
```

---

### Phase 4: Single-agent runner

Build:

```bash
factory spawn --count 1
factory watch
```

The runner should:

1. pick one ready task,
2. create a worktree,
3. claim the task,
4. create an agent prompt,
5. launch Claude Code or Codex,
6. stream logs,
7. detect completion/blockage,
8. run verification,
9. create an evidence packet.

Acceptance criteria:

```text
One agent can complete one task in an isolated worktree.
Logs are captured.
Verification commands run.
Evidence packet is produced.
Task is not closed without evidence.
```

---

### Phase 5: CodeScent integration

Add pre/post intelligence.

Before agent starts:

```text
repo map
relevant files
risk notes
suggested tests
```

After agent finishes:

```text
risk scan
new findings
test suggestions
evidence notes
```

Acceptance criteria:

```text
Agent prompt includes CodeScent context.
Evidence packet includes CodeScent result.
High-risk findings prevent auto-ready status.
```

---

### Phase 6: Safety integration

Add DCG and policy profiles.

Commands:

```bash
factory policy show
factory policy set implement
factory policy audit
```

Acceptance criteria:

```text
Destructive commands are blocked.
Force pushes are blocked.
Dangerous Git operations are blocked.
Production deploy commands are blocked by default.
Safety violations are logged as incidents.
```

---

### Phase 7: Multi-agent runner

Build:

```bash
factory spawn --count 3
factory simulate --agents 5
factory reclaim-stale
```

Add:

```text
worktree per task
file reservation
stale claim detection
agent identity
task assignment scoring
conflict detection
handoff generation
```

Acceptance criteria:

```text
Three agents can work simultaneously.
Factory avoids assigning conflicting tasks when possible.
Stale sessions are detected.
Blocked sessions produce handoffs.
No two agents intentionally edit the same reserved file without warning.
```

---

### Phase 8: Review and merge queue

Build:

```bash
factory review TASK_ID
factory pr TASK_ID
factory merge-ready
```

Flow:

```text
agent completes task
factory verifies
factory creates PR
review agent reviews PR
human reviews if required
merge queue merges when green
```

Acceptance criteria:

```text
Every completed task can produce a PR.
PR body includes evidence packet.
Low-risk tasks can be marked merge-ready.
High-risk tasks require human review.
```

---

### Phase 9: Dashboard

Start with a TUI or static HTML report.

Show:

```text
agents running
tasks ready
tasks blocked
tasks in review
verification failures
file conflicts
budget used
stale sessions
recent evidence
critical path
```

Commands:

```bash
factory watch
factory report
```

Do not overbuild the UI early.

A terminal dashboard plus generated Markdown reports is enough.

---

### Phase 10: 24/7 mode

Only after the above works.

Command:

```bash
factory autopilot
```

Autopilot should require explicit config:

```toml
[autopilot]
enabled = true
max_agents = 4
max_daily_cost_usd = 25
autonomy_level = "L2"
allowed_hours = "always"
allow_auto_merge = false
allow_deploy = false
require_human_for_high_risk = true
stop_on_repeated_failures = true
```

Acceptance criteria:

```text
Factory can run continuously.
It respects budget.
It pauses on repeated failures.
It pauses on safety incidents.
It does not merge/deploy beyond configured autonomy level.
```

---

## 16. A concrete first-week build

If we were starting this tomorrow, I would do this:

### Day 1: Repo and docs

Create:

```text
README.md
VISION.md
ARCHITECTURE.md
TASK_SCHEMA.md
EVIDENCE_SCHEMA.md
AUTONOMY_LEVELS.md
SAFETY_POLICY.md
```

Decide:

```text
Language for factory CLI
Initial task backend: br
Initial agents: Claude Code + Codex
Initial workspace mode: git worktree
Initial DB: SQLite
```

### Day 2: `factory init` and `factory doctor`

Implement environment detection and config generation.

### Day 3: TaskGraph adapter

Read ready tasks from `br`.

Show:

```bash
factory next
factory graph
```

### Day 4: Prompt envelope and one-agent launch

Manually select one task, create worktree, launch one agent.

### Day 5: Verification/evidence packet

Run test commands and produce:

```text
.factory/evidence/TASK_ID.json
.factory/evidence/TASK_ID.md
```

### Day 6: CodeScent pre/post hooks

Add CodeScent context before execution and risk scan after execution.

### Day 7: Two-agent supervised run

Run:

```bash
factory spawn --count 2
factory watch
```

The first milestone is not “build software 24/7.”

The first milestone is:

> Two agents complete two independent tasks in separate worktrees, with passing
> verification and reviewable evidence.

That is the seed of the factory.

---

## 17. My “best ideas” list

These are the ideas I think could make your project genuinely better than the
existing reference stack.

### 1. Plan readiness score

Before task generation, score the plan:

```text
Clarity: 72%
Acceptance coverage: 41%
Testability: 58%
Architecture completeness: 63%
Autonomy readiness: Not ready
```

This directly supports your personal workflow.

---

### 2. Requirement-to-task traceability

Every task links back to a plan section.

Every plan requirement links forward to tasks.

No orphan requirements. No orphan tasks.

---

### 3. Swarm dry-run simulator

Before launching agents, simulate:

```text
dependency bottlenecks
file conflicts
agent count recommendation
risky tasks
missing verification
best first wave
```

This prevents wasted agent time.

---

### 4. Evidence packets

Make evidence the atomic unit of trust.

Agents do not “say” they are done. They prove it.

---

### 5. Autonomy levels

Make autonomy explicit and configurable per repo/task.

This makes the project safer and more adoptable.

---

### 6. Agent reputation

Track which agents actually succeed.

Route future work based on observed performance, not vibes.

---

### 7. Stale-agent reaper

Detect loops, silence, repeated failures, and compaction drift.

Generate handoff summaries automatically.

---

### 8. Conflict heatmap

Show files/directories with active reservations, recent changes, and likely
contention.

Useful when running many agents.

---

### 9. Stop-the-line policy

If a critical gate fails, pause related work.

Example:

```text
Typecheck has failed on main.
Pause all tasks touching src/api until fixed.
```

This borrows from manufacturing discipline.

---

### 10. Factory retrospective

After each run:

```text
What failed?
Which tasks were underspecified?
Which tests were missing?
Which agents got stuck?
Which AGENTS.md rules should be updated?
Which plan sections caused confusion?
```

Then it proposes changes to `AGENTS.md`, `PLAN.md`, task templates, and safety
policy.

This is the real flywheel.

---

## 18. A simple mental model

I would describe the system like this:

```text
Planner
  turns human intent into executable task graph

Dispatcher
  chooses what should be worked on next

Worker
  runs coding agents in isolated workspaces

Inspector
  verifies changes and collects evidence

Coordinator
  manages mail, reservations, blockers, and handoffs

Guardian
  enforces safety policies

Historian
  records what happened and improves future runs
```

That is much easier to understand than a giant swarm architecture.

---

## 19. The architecture diagram

```text
                    ┌────────────────────┐
                    │     Human Plan      │
                    │ PLAN / ARCH / ADRs  │
                    └─────────┬──────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │  Plan Compiler      │
                    │ audit / import      │
                    └─────────┬──────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Task Graph Adapter  │
                    │ br / bd / GitHub    │
                    └─────────┬──────────┘
                              │
                              ▼
┌──────────────┐    ┌────────────────────┐    ┌──────────────┐
│ Agent Mail   │◄──►│ Factory Control    │◄──►│ CodeScent    │
│ coordination │    │ Plane / Scheduler  │    │ code intel   │
└──────────────┘    └─────────┬──────────┘    └──────────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Agent Adapters      │
                    │ Claude / Codex /... │
                    └─────────┬──────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Workspaces          │
                    │ worktree/container  │
                    └─────────┬──────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Verification Gates  │
                    │ tests/lint/build    │
                    └─────────┬──────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Evidence + PR Queue │
                    └────────────────────┘
```

---

## 20. My recommendation for the project’s first public promise

Do not promise:

> “Fully autonomous software development.”

Promise:

> “Turn a human-approved plan into coordinated, verified, multi-agent
> implementation work.”

That is more credible, safer, and more useful.

A good tagline:

> **An AI-first software factory for converting plans into verified pull
> requests.**

Or:

> **Local-first orchestration for autonomous coding agents.**

Or:

> **The missing control plane for multi-agent software development.**

---

## 21. The implementation plan I would hand to agents

This is the first version of the agent-executable plan I would create.

```markdown
# Epic 1: Factory CLI Foundation

## Task 1.1: Create CLI skeleton

Acceptance:

- `factory --help` works.
- Commands are registered for `init`, `doctor`, `graph`, `next`, `spawn`,
  `watch`.
- Config loading is implemented.

## Task 1.2: Implement config model

Acceptance:

- `.factory/config.toml` is parsed.
- Missing config produces useful errors.
- Defaults are documented.

## Task 1.3: Implement event ledger

Acceptance:

- SQLite DB is created under `.factory/events.sqlite`.
- Events can be appended and queried.
- Event schema includes timestamp, project, task, agent, type, payload.

# Epic 2: Project Bootstrap

## Task 2.1: Implement `factory init`

Acceptance:

- Creates `.factory/`.
- Creates default config.
- Creates prompt directory.
- Creates evidence directory.
- Creates starter `AGENTS.md` if absent.

## Task 2.2: Implement `factory doctor`

Acceptance:

- Checks git.
- Checks task backend.
- Checks available agents.
- Checks CodeScent.
- Checks DCG.
- Reports pass/fail clearly.

# Epic 3: Task Graph

## Task 3.1: Define TaskGraph interface

Acceptance:

- Interface supports list ready, get task, claim, block, close, dependencies.

## Task 3.2: Implement br adapter

Acceptance:

- Can list ready tasks.
- Can read task details.
- Can claim/update tasks.
- Can parse dependencies.

# Epic 4: Agent Execution

## Task 4.1: Define AgentAdapter interface

Acceptance:

- Interface supports start, stream events, cancel, collect result.

## Task 4.2: Implement Claude Code adapter

Acceptance:

- Can launch Claude Code with prompt file.
- Logs are captured.
- Exit status is recorded.

## Task 4.3: Implement Codex adapter

Acceptance:

- Can launch Codex CLI with prompt file.
- Logs are captured.
- Exit status is recorded.

## Task 4.4: Implement worktree manager

Acceptance:

- Creates one worktree per task.
- Cleans up after merge/abandon.
- Refuses to start if dirty state is unsafe.

# Epic 5: Verification

## Task 5.1: Define evidence schema

Acceptance:

- JSON schema exists.
- Markdown renderer exists.

## Task 5.2: Implement verification runner

Acceptance:

- Runs configured commands.
- Captures stdout/stderr.
- Records exit codes.
- Blocks task closure on failed required commands.

## Task 5.3: Generate evidence packets

Acceptance:

- Writes `.factory/evidence/TASK_ID.json`.
- Writes `.factory/evidence/TASK_ID.md`.
- Includes changed files, commit, commands, results, summary.

# Epic 6: CodeScent Integration

## Task 6.1: Add pre-task CodeScent context

Acceptance:

- Factory can call CodeScent repo/status/search tools.
- Agent prompt includes relevant context.

## Task 6.2: Add post-task CodeScent risk scan

Acceptance:

- Evidence packet includes CodeScent scan result.
- New high-risk findings block auto-ready status.

# Epic 7: Multi-agent Scheduling

## Task 7.1: Implement scheduler

Acceptance:

- Selects ready tasks.
- Avoids file conflicts when likely files are known.
- Respects max concurrency.

## Task 7.2: Implement stale claim reaper

Acceptance:

- Detects inactive sessions.
- Generates handoff file.
- Marks task blocked or ready for retry.

## Task 7.3: Implement `factory spawn --count N`

Acceptance:

- Starts N workers on independent tasks.
- Records session state.
- Does not exceed concurrency limit.

# Epic 8: Review Queue

## Task 8.1: Generate PR body

Acceptance:

- PR body includes task, summary, acceptance criteria, verification, evidence
  link.

## Task 8.2: Implement review status

Acceptance:

- Task can be marked needs-review, approved, rejected.
- Rejected task includes reviewer notes.

# Epic 9: Dashboard

## Task 9.1: Implement `factory watch`

Acceptance:

- Shows active agents.
- Shows task states.
- Shows failures.
- Shows stale sessions.
- Refreshes live.

## Task 9.2: Implement static report

Acceptance:

- Generates Markdown or HTML report.
- Includes graph summary, evidence, failures, costs if available.
```

That is enough to start.

---

## Final opinion

You are right that the reference system is too complicated. But the answer is
not to make agents smarter or more autonomous at first.

The answer is to make the factory more disciplined.

The project should be built around five hard rules:

1. **No task without acceptance criteria.**
2. **No work without a claim and workspace.**
3. **No completion without evidence.**
4. **No parallelism without conflict awareness.**
5. **No increasing autonomy without measured trust.**

If you nail those five, you can start with two agents and grow to ten, twenty,
or more.

The real product is not “agents coding all night.”

The real product is **a trustworthy operating system for autonomous software
work**.

[1]:
  https://docs.anthropic.com/en/docs/claude-code/overview
  "Overview - Claude Code Docs"
[2]:
  https://agent-flywheel.com/workflow
  "Agent Flywheel - AI Agents Coding For You"
[3]:
  https://agent-flywheel.com/complete-guide
  "The Complete Flywheel Guide - Planning, Beads & Agent Swarms | Agent Flywheel"
[4]:
  https://raw.githubusercontent.com/gastownhall/beads/main/README.md
  "raw.githubusercontent.com"
[5]:
  https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/README.md
  "raw.githubusercontent.com"
[6]:
  https://docs.anthropic.com/en/docs/claude-code/cli-reference
  "CLI reference - Claude Code Docs"
[7]: https://developers.openai.com/codex/cli "CLI – Codex | OpenAI Developers"
[8]: https://opencode.ai/ "OpenCode | The open source AI coding agent"
[9]:
  https://github.com/aider-ai/aider
  "GitHub - Aider-AI/aider: aider is AI pair programming in your terminal · GitHub"
[10]: https://goose-docs.ai/ "goose | Your open source AI agent"
[11]: https://agents.md/ "AGENTS.md"
[12]:
  https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/README.md
  "raw.githubusercontent.com"
[13]:
  https://raw.githubusercontent.com/robertguss/code-scent-mcp/main/README.md
  "raw.githubusercontent.com"
[14]:
  https://raw.githubusercontent.com/robertguss/code-scent-mcp/main/docs/mcp-tools.md
  "raw.githubusercontent.com"
[15]:
  https://raw.githubusercontent.com/robertguss/code-scent-mcp/main/docs/workflows.md
  "raw.githubusercontent.com"
[16]:
  https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/README.md
  "raw.githubusercontent.com"
[17]:
  https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/README.md
  "raw.githubusercontent.com"
[18]:
  https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/README.md
  "raw.githubusercontent.com"
[19]:
  https://modelcontextprotocol.io/docs/getting-started/intro
  "What is the Model Context Protocol (MCP)? - Model Context Protocol"
