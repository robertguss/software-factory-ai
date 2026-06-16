# Gemini 3.1 Pro Implementation Plan

The vision of a fully autonomous 24/7 software factory is the holy grail of
current AI engineering, but the existing implementations out there—like the
agentic flywheel you linked—suffer from extreme over-engineering. They try to
bootstrap an entire Ubuntu VPS with Tmux sessions, global dependencies, and
messy bash scripts. It creates a fragile state machine on the host OS.

We can build something much cleaner, rooted in a post-SaaS philosophy where you
own the local-first infrastructure, and the complexity is tightly contained.

Before diving into the architecture, I am going to challenge a few of the core
assumptions in your premise to ensure this system actually scales without
collapsing under its own weight.

### The Pushback: Challenging the 10-Agent 24/7 Model

**1. The Collision Problem (Git Thrashing)** Spinning up 10 agents to work in
parallel on the same codebase sounds great in theory, but in practice, it
creates a massive bottleneck at the merge layer. If 10 agents are touching the
same monolith, they will create constant merge conflicts, overwrite each other's
state, and break dependent interfaces. _The Insight:_ Parallel agents cannot
work on shared files. The system must enforce strict domain isolation. The
architectural plan you provide must be broken down by the "Foreman" agent into
strictly independent bounded contexts (e.g., Agent 1 gets the React frontend
components, Agent 2 gets the FastAPI routes, Agent 3 gets the database schema).
They must work on isolated feature branches.

**2. The API Burn Rate vs. Local Inference** Running 10 instances of a frontier
model (like Claude 3.5 Sonnet) 24/7 via API will result in an astronomical bill.
_The Insight:_ We need a tiered intelligence model. The "Foreman" and "Reviewer"
agents use the heavy, expensive API models because they require deep reasoning.
The 10 "Worker" agents should ideally run against local LLMs (perhaps 70B
parameter models running on a dedicated Apple Silicon or NVIDIA workstation) for
the brute-force iterative execution of writing tests and implementing standard
functions.

**3. Separation of Concerns in Data** A common trap in agentic systems is mixing
the agent's memory with the target application's state. _The Insight:_ The
internal application database that manages the factory's orchestration (the task
queue, agent memory, and dependencies) must remain strictly separate from the
external data source (the actual code repositories and databases being built).

### The Software Factory Architecture

To avoid reinventing the wheel, we will use a highly decoupled, state-driven
architecture.

**Layer 1: The Control Plane (The Task Graph)** Inspired by Beads, we need a
persistent, structured memory for the agents. Instead of giving agents messy
Markdown files that grow out of control, we use a local, lightning-fast database
like DuckDB. This database holds Epics, Tasks, Dependencies (`blocks`,
`blocked_by`), and Agent Assignments.

**Layer 2: The Sensory Layer (Code-Scent)** `code-scent-mcp` is perfect here
because of its strict boundaries. It writes its state to `.codescent/` without
aggressively editing the source files. Every time an agent picks up a task, its
first move is to use CodeScent to index the repo, pull the deterministic
code-health issues, and find the exact context it needs before writing a single
line of code.

**Layer 3: The Execution Environment** Instead of a complex VPS bootstrapping
script, the orchestrator (which could be a lightweight Python runner or a
workflow engine like Windmill) queries the DuckDB database:
`SELECT * FROM tasks WHERE blocked_by = 0 AND status = 'ready'`. For each ready
task, it spins up an ephemeral Docker container.

Inside that container, we run Claude Code. Instead of relying on brittle manual
copying or custom wrapper scripts, the orchestrator passes a specific slash
command to the Claude Code CLI (e.g., `/execute task-123`) which automates the
file handling and directs the agent to begin its loop.

### The Implementation Plan

Here is how we build this, starting today.

#### Phase 1: The Analog-to-Digital Handoff

1. You do the deep, focused thinking. Whether that starts offline with index
   cards or a Zettelkasten to map out the conceptual dependencies, you
   ultimately distill your intent into a master Product Requirements Document
   (PRD).
2. You feed this PRD to the **Foreman Agent**. The Foreman's _only_ job is
   parsing your spec into the DuckDB task graph. It breaks the PRD down into a
   dependency tree (Epic -> Story -> Task) and inserts them into the database.

#### Phase 2: The Orchestration Daemon

We build a simple, single-binary orchestrator (in Rust or Go, or just a robust
TypeScript loop) running on your VPS.

1. **The Poller:** Every minute, it checks the database for unblocked tasks.
2. **The Dispatcher:** When a task is free, it checks out a new git branch from
   `main` (e.g., `feat/agent-task-45`).
3. **The Worker:** It spawns an isolated execution environment, injecting
   `code-scent-mcp` as the primary tool. It prompts Claude Code: _"You are
   responsible for Task 45. Use CodeScent to orient yourself. Write the tests.
   Implement the code. Use slash commands to manage your files. When tests pass,
   commit and exit."_

#### Phase 3: The QA and Merge Gate

When a Worker container exits successfully:

1. The Orchestrator triggers the **Reviewer Agent**.
2. The Reviewer uses CodeScent's deterministic CI evals (`codescent ci`) to scan
   the diff on the worker's branch.
3. If the code is clean, well-tested, and doesn't break the build, the Reviewer
   merges it into `main` and marks Task 45 as `completed` in DuckDB.
4. This action cascades through the database, instantly unblocking downstream
   tasks. If the review fails, it creates a new feedback task, blocking the
   merge, and puts it back in the queue.

### Why this is better

This approach reflects a refactored mind applied to software automation. By
isolating the orchestration state from the codebase, using ephemeral execution
environments instead of dirty VPS host OS mutations, and leveraging `code-scent`
for safe context-gathering, you eliminate the fragility of the flywheel example.

If this direction resonates, our next step is to define the exact schema for the
internal orchestration database. How deep do you want the Foreman agent to go
when breaking down your PRD? Should it write the test specifications as part of
the breakdown, or leave that to the individual workers?
