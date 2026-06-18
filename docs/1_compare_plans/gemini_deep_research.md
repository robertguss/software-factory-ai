# **Strategic Architecture and Implementation Roadmap for the Conveyor Autonomous Software Factory**

## **Executive Foundation and Strategic Imperatives**

The evolution of the Conveyor system marks a definitive transition from loosely
coordinated, human-tended script environments to a fully autonomous,
deterministic, and self-healing software factory.1 Foundational efforts in Phase
0 and Phase 1 have successfully established a critical tracer bullet, proving
that a deterministic execution environment built atop the Elixir/BEAM virtual
machine can effectively orchestrate the judgment-driven operations of large
language models.1 This baseline architecture inherently rejects the fragility of
the earlier "agentic-coding-flywheel" paradigms, which relied on complex
advisory locks, bespoke synchronization tools, and the highly dangerous practice
of permitting agents to commit directly to the main trunk repository.1  
Instead, the Conveyor architecture enforces the unyielding "Determinism-Boundary
Law," a principle dictating that deterministic systems must exclusively own
validation and state transitions, while artificial intelligence agents are
relegated strictly to heuristic judgment and implementation generation.1 Agents
operate within thoroughly isolated Docker container workspaces, completely
eliminating file reservation collisions, while an event-sourced ledger
implemented via the Ash Framework acts as the system's immutable institutional
memory.1  
As the foundational single-slice execution loop solidifies, the strategic
imperative shifts toward architecting the subsequent phases of operation. This
document synthesizes the existing array of twenty advanced capabilities
(designated C1 through C20) 1 while simultaneously introducing a suite of highly
ambitious, pragmatic extensions designed to maximize the system's autonomy,
economic efficiency, and antifragility. The forthcoming phases are categorized
into distinct strategic pillars, detailing the precise database structures,
orchestration patterns, and algorithmic models necessary for scaling from a
single task loop to a highly concurrent swarm intelligence.

## **Pillar I: Plan Ingestion, Legibility, and Semantic Firewalls**

The transition from a human-provided conceptual plan to thousands of lines of
production-grade code necessitates an absolutely flawless decomposition and
ingestion process. If ambiguity or logical contradiction is permitted to enter
the autonomous execution swarm, it compounds exponentially across dependency
graphs, resulting in circular agent failures, wasted computational resources,
and a degradation of system trust. The subsequent capabilities establish a
rigorous, highly legible ingestion pipeline that mathematically guarantees the
soundness of the work graph prior to execution.

### **The Executable Plan Workbench**

Before any agent is dispatched, the system must parse the initial plan into a
normalized, dependency-ordered graph of discrete tasks, referred to as Slices.1
The Executable Plan Workbench serves as the interactive, visual projection of
this normalized plan graph.1 Operating as an interactive "compiler for work,"
this control plane prevents the system from feeling like an opaque swarm,
allowing operators to understand, inspect, and approve multi-Slice workflows
before they are executed.1  
To ensure structural readiness for this workbench in the immediate term, Phase
0/1 must incorporate a specific architectural seam. The PlanAudit step must be
engineered to emit a content-addressed graph artifact, the PlanGraphProjection,
which strictly adheres to a predefined JSON schema designated
conveyor.plan\_graph@1.1 This schema comprehensively models all requirements,
acceptance criteria, Slices, conflict domains, and required human decisions.1  
Building upon this foundation, an ambitious extension of the Workbench involves
the implementation of a preemptive Abstract Syntax Tree (AST) overlay. Rather
than merely viewing text-based requirements, the Workbench could leverage native
Elixir language servers and tree-sitter parsers to visually project the
anticipated structural changes onto the existing codebase architecture. By
mapping the impending Slices directly onto a dependency graph of the current
source code, operators can instantly visualize which specific modules and
functions will be mutated by the swarm, providing a highly intuitive mechanism
for detecting unintended scope creep before a single token of generation is
purchased.

### **Spec Interrogation and Micro-Negotiation**

To eliminate failures at their source, a Spec Interrogator will be integrated
into the Phase 2 decomposition pipeline.1 This mechanism acts as a pre-execution
firewall, analyzing input specifications and Agent Briefs to flag logical
inconsistencies, missing parameters, or unresolvable ambiguities before a Slice
is permitted to transition into a ready-for-agent state.1  
When the Spec Interrogator identifies a potential ambiguity, the system does not
immediately halt and await human intervention. Instead, it enters a structured
resolution loop utilizing Slice-Contract Micro-Negotiation.1 This capability
permits automated, low-stakes micro-amendments between the implementing agent
and the contract-authoring system.1 For example, if a database schema migration
Slice specifies a new column but omits the nullability constraint, the agents
can programmatically negotiate and resolve the parameter without escalating to a
human operator.  
However, if the ambiguity threatens macro-architectural stability, the system
invokes the Plan Amendment Proposals protocol.1 This utilizes an explicitly
reserved off-ramp state machine alias, contract_disputed, which currently
defaults to a parked behavior in Phase 1\.1 In Phase 2, the contract_disputed
state will actively route the Slice to the human operator, presenting a
machine-generated set of proposed redlines for approval.1 This tiered approach
ensures the swarm exclusively operates on logically sound contracts.

### **Semantic Interface Firewalls and Schema Drift Prevention**

In a highly concurrent swarm environment, multiple agents may simultaneously
attempt to modify interacting components. The Semantic Interface Firewall is
designed to prevent integration drift across APIs, database schemas, and event
payloads.1  
To prepare for this in Phase 1, the system must be configured to accept
structured interface values—defining key types such as HTTP endpoints, public
Elixir functions, and Postgres tables—instead of unstructured free-text
strings.1 In Phase 4, this firewall hardens into a blocking gate stage. If an
agent attempts to alter a public interface that serves as a dependency for an
in-flight parallel Slice, the firewall mechanically rejects the change.1  
An advanced, pragmatic expansion of this concept involves the integration of an
autonomic backward-compatibility verification engine. Rather than merely
blocking changes to interfaces, the firewall could automatically generate and
enforce deprecation wrappers. If an agent determines that an API route must be
modified to satisfy a new requirement, the firewall would require the agent to
preserve the original route, mapping it to the new underlying logic, thereby
mathematically guaranteeing that no downstream client is broken by the swarm's
execution.

| Firewall Target    | Phase 1 Seam Requirement          | Phase 4 Blocking Behavior             | Proposed Advanced Extension                   |
| :----------------- | :-------------------------------- | :------------------------------------ | :-------------------------------------------- |
| **REST APIs**      | Structured HTTP route definitions | Reject unapproved parameter mutations | Auto-generation of V1/V2 routing wrappers     |
| **Database**       | Structured table and column keys  | Reject destructive column drops       | Mandatory soft-delete and migration shadowing |
| **Internal Calls** | Public function signatures        | Reject signature changes              | AST-aware structural dependency diffing       |
| **Event Bus**      | Typed payload schemas             | Reject payload key deletions          | Automatic payload versioning and translation  |

### **Simulation and Predictive Economics**

Before committing expensive computational resources to a complex epic, Conveyor
will execute a Swarm Dry-Run Simulator 1 alongside a Plan Simulator.1 By
simulating swarm execution pathways, the system generates predictive scheduling
models, cost foresight, and conflict domain maps.1  
The simulator leverages historical distributions of time and cost metrics
derived from similar Slice archetypes.1 To ensure the simulator has sufficient
operational data to function in Phase 6, Phase 0/1 must incorporate a crucial
seam into the Slice / AgentBrief schema: the addition of a stable archetype_key
(e.g., "crud_endpoint", "pure_refactor", "schema_migration").1 By processing the
normalized graph prior to execution, human approvers are presented with an
expected-value calculus, clearly indicating whether massive parallel execution
is computationally efficient or if deeper spec refinement is the optimal path
forward.1

## **Pillar II: The Economic Engine and Adaptive Swarm Routing**

A profound limitation of the baseline "agentic-coding-flywheel" is its
prohibitive operational cost, frequently exceeding $2,000 per month due to the
continuous utilization of flagship models for all tasks regardless of
complexity.1 The next iteration of the Conveyor architecture introduces an
Ash-backed economic governor and empirical routing systems designed to
dynamically optimize the token-to-value ratio.1

### **Outcome-Conditioned Routing and the Agent Skill Graph**

To dismantle monolithic model dependency, Conveyor implements an
Outcome-Conditioned Model Router, heavily augmented by an Agent Skill Graph.1
This system functions as an online bandit routing mechanism.1 Instead of
statically assigning flagship models to every task, the router analyzes
historical success rates categorized by the intersection of model identity and
task archetype.1  
Over time, the system will empirically deduce that lightweight, inexpensive
models are highly capable of executing a "pure_refactor" archetype, while
complex "database_migration" Slices strictly necessitate a highly parameterized
model.1 This guarantees the most competent models are reserved exclusively for
the tasks uniquely suited to their capabilities.1 To support this continuous
learning, Phase 0/1 must meticulously log the model_id, cost_cents,
wall_clock_ms, and the archetype_key within the RunAttempt and RunLedger
database structures.1  
An ambitious extension of this economic routing involves real-time commodity
market hedging. The Conveyor BEAM conductor could be engineered to continuously
poll token pricing across various model providers. If a specific API experiences
a latency spike or a price surge, the Dispatcher could automatically failover to
a locally hosted open-weight model for purely mechanical verification tasks,
ensuring the factory's operational costs remain strictly beneath a predefined
threshold.

### **Speculative Execution and the Dispatcher Scoring Algorithm**

For Slices positioned strictly on the critical path of a project, the routing
engine introduces Best-of-N Speculative Execution.1 Operating within the
isolated Docker containers orchestrated by the Elixir BEAM Conductor 1, the
system will deliberately spawn multiple simultaneous, competing implementations
of the exact same Slice.1 These competing agents may utilize different base
models, varied temperature settings, or distinct architectural prompts.  
Because isolated container workspaces prevent the file reservation collisions
and trunk poisoning inherent in older flywheel designs 1, these agents can race
without risk. The first implementation to successfully pass the verification
gate is immediately merged via the queue, and the competing runs are ruthlessly
terminated by the BEAM supervisor. While seemingly resource-intensive at the
micro-level, Best-of-N execution eliminates macro-level tail-latency bottlenecks
on critical path tasks, proving economically superior to leaving downstream
agents parked for extended periods.1  
To manage the execution queue, the system utilizes a dispatcher scoring function
calculating: priority × critical-path × unblock-count × model-fit.1 Tasks with a
highly positive expected value and a high unblock-count are aggressively
prioritized, maximizing the swarm's throughput while minimizing idle API
expenditure.1

### **Expected-Value Attention Queues**

When all automated avenues fail or when a task is mathematically determined to
require human oversight, the system utilizes the Expected-Value Human Attention
Queue.1 Rather than bombarding the human operator with an undifferentiated
stream of alerts, this queue algorithmically ranks blocked runs based on their
critical-path weight, blast radius, and predicted resolution cost.1 This ensures
that human bandwidth—the most expensive resource in the factory—is leveraged
exclusively where it delivers the maximum systemic value.1

| Routing Mechanism         | Execution Trigger                   | Economic Rationale                             | BEAM / Orchestration Requirement                     |
| :------------------------ | :---------------------------------- | :--------------------------------------------- | :--------------------------------------------------- |
| **Empirical Router**      | Standard ready-for-agent transition | Matches model cost to archetype difficulty     | Historical query of model × archetype success        |
| **Best-of-N Speculation** | Critical path blocker detected      | Trades compute token cost for wall-clock speed | Supervisor spawning multiple parallel workers        |
| **Cost Governor Abort**   | Run-away API loop detected          | Prevents catastrophic billing overruns         | Ash state machine kill-switch                        |
| **Attention Queue**       | Autonomous avenues exhausted        | Maximizes leverage of human intervention       | Weighted priority sorting based on DAG unblock count |

## **Pillar III: Context Assembly and Active Supervision**

A profound architectural flaw in earlier agentic tools was the reliance on
static memory buffers or naive vector searches without closed-loop feedback
regarding the actual utility of that injected memory.1 The generation of
production-quality code is entirely dependent on the quality of the surrounding
context. Conveyor's execution pipeline introduces compounding, self-optimizing
context assembly mechanisms to achieve optimal token density.

### **The Self-Training Context Scout**

In Phase 7, Conveyor deploys a Self-Training Context Scout designed to
drastically improve the signal-to-noise ratio in agent prompts.1 Traditional
systems blindly pack conceptually related files into an agent's context window.
The Context Scout dynamically evaluates the empirical overlap between what files
or symbols were injected into the context versus what the agent actually read,
utilized, or edited during its execution trace.1  
To achieve this without necessitating destructive database schema rewrites in
the future, an embedded JSON document designated context_usage must be
pre-allocated within the Evidence resource during Phase 1\.1 By recording raw
usage telemetry logs, the system feeds an Ash Framework pgvector database.1
Future queries against this vector store will heavily weight the structural
dependencies empirically proven to be relevant in past successful runs,
continuously compounding the system's institutional memory.1  
A highly pragmatic extension of this Context Scout involves the concept of
"Ghost Context." When an agent attempts a task that has historically suffered
high failure rates, the Scout could automatically query the pgvector store for
the Evidence Dossiers of previously successful runs of the same archetype. By
natively injecting the execution trace and abstract syntax tree diffs of a past
success directly into the system prompt, the agent is provided with an explicit,
mathematically proven template, drastically reducing hallucination rates on
complex architectural modifications.

### **Continuous In-Container Feedback: The Gate-as-Tutor**

The traditional binary pass/fail verification gate forces an agent to completely
compile and submit its entire body of work before discovering a trivial syntax
error, resulting in massive API rework costs and wasted compute cycles.1 The
Gate-as-Tutor capability restructures the execution environment to provide
continuous, iterative, in-container feedback.1  
Instead of waiting for the final epic-level gate, lightweight advisory
checks—such as formatting validations, simple type-checks, and deterministic
code-health delta scans provided by the local CodeScent MCP server 1—are
executed concurrently within the agent's isolated workspace.1 This significantly
tightens the feedback loop, drastically cutting required rework.1 To prepare the
database, the RunCheck / CommandResult schemas must be modified in Phase 1 to
include a check_phase field (defaulting to final), an iteration_index, and a
boolean advisory flag.1  
When critical errors are encountered, the Failure Triage Autopilot intercepts
the stack trace.1 Relying on a stable failure and next-action taxonomy, the
autopilot automatically generates precise rework recipes, mints regression
mutants, or suggests specific plan amendments, radically accelerating the
unparking of blocked execution loops.1

### **The Gate-Preserving Patch Shrinker**

Agents frequently over-edit files, inadvertently introducing unnecessary
formatting changes or tangential refactors that bloat differential views and
exponentially increase merge conflict probabilities. The Gate-Preserving Patch
Shrinker acts as an intermediary post-execution filter.1  
Once a Slice successfully passes all gate requirements, this mechanism
automatically shrinks the code edits into minimal safe diffs at the hunk level.1
It iteratively removes lines from the diff, continually re-running the fast
verification gate. If the gate continues to pass, the excised lines are
permanently discarded. This ensures that only the absolute minimum required code
changes are merged into the integration branch, minimizing risk and drastically
reducing the surface area for future integration collisions.1  
An advanced, synergistic idea to augment the Patch Shrinker is the deployment of
an AST-Aware Semantic Merge Conflict Resolver. If an agent writes code that
collides with the main trunk, textual Git diffs are inherently fragile and
frequently require human intervention. By integrating native language parsers,
the swarm could understand the semantic nature of the collision (e.g., a
function signature was updated on the trunk while the agent was utilizing the
old signature) and structurally rewrite the AST to natively merge the features,
bypassing traditional text-based conflict failures entirely.

## **Pillar IV: The Antifragile Verification Pyramid**

As explicitly defined in the Conveyor strategic documentation, the generation of
code is trivial; establishing mathematical trust in that code is the true
bottleneck of autonomy.1 The verification gate acts as the system's most
critical, heavy-duty component, serving as the sole trusted stand-in for human
review during unattended operations.1 To guarantee trunk safety, the gate cannot
be static; it must operate as an antifragile, multi-tiered pyramid.1

### **Separation of Duties and the Test Architect**

A foundational security principle of the autonomous factory is the strict
separation of duties: the implementing agent is structurally prohibited from
writing its own acceptance criteria or its own red-team tests.1 If an AI model
authors both the implementation and the test suite, it is highly incentivized to
author vacuous tests that mathematically guarantee a false-positive pass.1  
To rigorously enforce this boundary, the Phase 2 architecture introduces a
dedicated Test Architect role.1 During the planning and decomposition phase, the
Test Architect generates the required behavioral tests, property constraints,
and acceptance thresholds, committing them into a strictly read-only contract.1
The execution loop flows directionally: the Test Architect establishes the
restrictive Red state, the Implementer achieves the passing Green state, and the
deterministic CodeScent server enforces the Refactor state by unequivocally
rejecting any detected code smell regressions.1 This workflow is secured by Ash
Framework authorization policies that physically prevent the implementer's
credentials from modifying the test files.

### **The Contract Test Integrity Sentinel and Mutation Scanning**

To safeguard the ledger against vacuous or flaky tests, Conveyor implements the
Contract Test Integrity Sentinel.1 Operating strictly at the lock-time phase,
this sentinel establishes an empirical truth baseline by deliberately modifying
runtime conditions—such as actively stubbing interfaces, forcing network
timeouts, or corrupting memory allocations—to ensure the test suite genuinely
fails when it is supposed to fail.1  
Simultaneously, the gate executes Mutation-Tested Contracts.1 By
programmatically injecting semantic defects into the system (e.g., swapping
mathematical operators, nullifying variables, or reversing conditional logic),
the gate calculates a precise mutation score representing the exact percentage
of introduced bugs successfully caught by the Test Architect's contract.1  
A database seam in the TestPackCalibration table must be introduced immediately
in Phase 1, reserving a nullable contract_strength_status field with the
enumerations not_assessed, strong, and weak.1 Contracts failing to meet minimum
mutation score thresholds are instantly quarantined, preventing silent
false-positives from corrupting the continuous integration ledger.1

### **Escaped Defects and Antifragile Regression Mutants**

No verification gate is mathematically flawless, and critical bugs will
inevitably escape into the development or main branches.1 The Phase 5
antifragile spine, Regression Mutants from Escaped Defects, transforms these
inevitable failures into permanent systemic immunities.1  
When a post-integration defect is flagged, Conveyor isolates the exact offending
commit, captures the specific failing condition, and automatically mints a new
regression mutant package.1 This new mutant is permanently appended to the
testing corpus, guaranteeing that the factory can never mathematically merge
that specific defect pattern again.1 To facilitate this capability without
massive schema migrations, the conveyor.canary_mutant@1 schema must be
established in Phase 1 as an inert fixture, reserving critical fields such as
mutant_id, origin (escaped_defect, authored), and the base_solution_ref
cryptographic blob pointers.1

### **Adversarial Gate Self-Play**

Leveraging the continuously compounding corpus of minted regression mutants, the
system will initiate Adversarial Gate Self-Play during idle compute cycles.1 A
specialized, highly incentivized Red-Team Agent is tasked with rewriting
functionally correct code to deliberately introduce subtle logic bombs, race
conditions, or memory leaks designed to evade the current testing contracts.1  
If the Red-Team Agent successfully sneaks a generated mutant past the
deterministic verification gate, a critical vulnerability is immediately logged,
and the Test Architect is automatically prompted to strengthen the acceptance
criteria.1 This continuous, localized self-play mirrors generative adversarial
network methodologies, ensuring that as the implementing agents grow more
sophisticated, the verification gate simultaneously hardens its defensive
perimeter.  
An incredibly ambitious extension to this self-play is the introduction of a
"Chaos Monkey" Evaluator Agent. During the execution of the test suite, this
agent's sole purpose is to randomly terminate dependent BEAM processes, sever
database connections, or flood the application with malformed network requests.
This ensures that the implementer has not only written functionally correct
code, but has fundamentally architected highly resilient, fault-tolerant
fallback mechanisms that can survive catastrophic infrastructural decay.

| Verification Tier    | Primary Objective          | Execution Trigger           | Gate Strength                                               |
| :------------------- | :------------------------- | :-------------------------- | :---------------------------------------------------------- |
| **Bead Gate**        | Fast task-level validation | Post-implementation compile | Build \+ AC Tests \+ CodeScent Delta Check 1                |
| **Epic Gate**        | Feature-level integration  | Epic completion             | Full suite \+ Property Tests \+ Mutation Scan \+ Red-Team 1 |
| **Phase Gate**       | Release authorization      | Branch promotion            | Deep Mutation \+ E2E \+ Security Audit \+ Dependency Scan 1 |
| **Adversarial Gate** | Antifragility training     | Idle compute cycles         | Red-Team mutant injection vs. Test Architect contracts      |

### **Risk-Proportional Verification and Test Planners**

Executing the entirety of the epic-level verification gate for a trivial
cascading style sheet modification is economically and computationally ruinous.1
The Scope-Creep and Blast-Radius-Proportional Gate dynamically solves this by
calculating the specific call-graph blast radius of a merged patch.1  
If an agent modifies a highly isolated, leaf-node module, the gate automatically
scales down its intensity to localized unit tests. If a core data model or
highly depended-upon function is altered, the system automatically elevates the
testing intensity to exhaustive Phase Gate levels, actively intercepting
unintended scope-creep.1 Concurrently, the Test Impact and Verification Planner
dynamically designs the most economically viable testing pathway that still
mathematically satisfies the stringent safety requirements, drastically lowering
the computational overhead of continuous verification cycles.1

## **Pillar V: Autonomy Governance and Legacy Code Adoption**

The ultimate objective of the Conveyor architecture is a self-sustaining
ecosystem capable of operating completely unattended, managing its own internal
health metrics, and intelligently onboarding undocumented, brownfield
codebases.1 The final set of capabilities constructs the sophisticated autonomy
governance layer and ensures rapid market adoption.

### **Merge Trust Scores and the Autonomy Readiness Center**

Systemic autonomy is not a binary toggle; it is a continuously measured, highly
calibrated variable. The Merge Trust Score synthesizes a vast array of empirical
metrics—mutation survival rates, differential behavior analyses, test sentinel
integrity, and historical canary performance—to output a precise risk profile
for every integration event.1  
This empirical score directly feeds the Autonomy Readiness Control Center, an
operator control surface that continuously monitors system health to dynamically
govern autonomy elevations.1 If the Merge Trust Score for a specific archetype
remains consistently high across hundreds of runs, the per-archetype autonomy
dial automatically limits human intervention, granting the swarm explicit
permission to merge that specific task class directly to the protected branches
without human review.1 Conversely, if false-negative rates spike or test
sentinel integrity drops, the dial acts as an automated "stop-the-line" kill
switch, globally downgrading the swarm's earned authority until an operator can
thoroughly inspect the Evidence Dossiers.1

### **The Evidence Time Machine and Deterministic Rule Graduation**

Every attempted task in the Conveyor system produces an event-sourced Evidence
Dossier containing exact code diffs, terminal outputs, verification results, and
context usage telemetry.1 The Evidence Time Machine converts this vast, static
ledger into a highly actionable forensics and run-diffing tool.1  
Operators and supervisor agents can utilize this time machine to mathematically
audit system decisions, stepping backward through an agent's reasoning process
state-by-state to debug execution failures and refine trust parameters.1 When
recurrent failure modes are identified through forensic analysis, the Lessons
That Graduate to Deterministic Rules capability is triggered.1  
Through this process, the swarm learns to identify probabilistic failure
patterns and codifies them into mechanical, deterministic rules (e.g., creating
a new custom CodeScent abstract syntax tree linting rule), permanently
eliminating the need to rely on probabilistic LLM reasoning for known
architectural pitfalls.1 To enable this transition, an optional rule_key slug
must be added to the standard findings embedded Elixir schema in Phase 1\.1

### **Trunk Guardian and Behavior-Lock Differential Testing**

If a highly sophisticated regression successfully bypasses the epic gate and
poisons the main trunk repository, the Auto-Bisect \+ Auto-Revert Trunk Guardian
acts as an immediate, automated incident responder.1 Operating via a dedicated
Oban worker queue, the guardian detects integration trunk failures,
systematically bisects the commit history to isolate the offending merge, and
performs an automatic git revert to stabilize the repository, operating
autonomously at 3:00 AM without human intervention.1  
To protect critical existing functionality during aggressive system refactors,
Conveyor utilizes Behavior-Lock Differential Testing.1 By simultaneously
executing the legacy code path and the agent-modified code path side-by-side
with identical, high-volume inputs, the gate enforces strict mathematical output
parity.1 This guarantees that while the internal algorithms of a module may be
heavily optimized by the swarm, the external behavioral contract remains
absolutely identical.  
An ambitious paradigm to enhance the Trunk Guardian is the deployment of
Autonomous Feature Flagging (Dark Launching). Instead of immediately reverting a
problematic merge, the system could be engineered to automatically wrap all
swarm-generated code within dynamic feature flags. When merged to the trunk, the
new code remains dormant. The system then routes a tiny percentage of staging
traffic through the new implementation, monitoring for error spikes. If
stability is confirmed, the system autonomously ramps up the traffic allocation.
If errors occur, the flag is instantly toggled off, providing perfect trunk
safety without the need for destructive git operations.

### **Legacy Integration: Brownfield Onboarding and Trace-to-Contract Synthesis**

A software factory that can only construct greenfield applications is of highly
limited industrial utility. Conveyor must be inherently capable of adopting
massive, poorly documented legacy codebases. The Brownfield Onboarding Safety
Net is designed to establish a golden-master behavioral baseline for untested,
legacy repositories during the initial ingestion phase.1  
Because legacy systems fundamentally lack predefined Test Architect contracts,
the system deploys the Runtime Trace-to-Contract Synthesizer.1 By securely
capturing execution traces, application telemetry, database queries, and live
network requests from the legacy software operating in a staging environment,
the Synthesizer automatically generates an exhaustive behavioral testing
corpus.1  
This machine-generated test suite serves as the foundational safety net,
allowing the deterministic verification gate to enforce differential behavior
locks even on code it did not originally author.1 By automatically capturing
these traces, the system can retroactively build the missing acceptance criteria
required to bring the legacy code under the strict jurisdiction of the
autonomous factory.  
Finally, as the verification gate hardens into an impenetrable perimeter, its
utility transcends internal operations. The Conveyor Gate as a Standalone PR
Reviewer capability packages the entire deterministic evaluation
engine—comprising the CodeScent health scanner, mutation scoring, blast-radius
analysis, and differential lock testing—into a discrete, consumable product
surface.1 This allows external human developers to submit traditional pull
requests to a repository and receive the exact same rigorous, multi-tiered
algorithmic scrutiny that governs the autonomous swarm, establishing a
incredibly powerful adoption wedge for the Conveyor ecosystem.1

## **Phase 6-8 Advanced Exploratory Workstreams (Net-New Architectures)**

To fully realize the ambitious mandate of generating highly creative,
unrestrained capabilities, the architecture must look beyond the immediate
validation of code and delve into the autonomic management of infrastructure,
deep architectural debate, and continuous structural compression. The following
exploratory workstreams are proposed as net-new architectures to be integrated
following the stabilization of Phase 5\.

### **Workstream Alpha: The Autonomic Database Migrator with Reversible Dry-Runs**

Database migrations are the highest-risk operations in any software factory, as
destructive data loss cannot be remediated via a simple code revert. The
Autonomic Database Migrator is proposed as an intelligent, BEAM-supervised
process that manages schema evolution.  
When an agent proposes a database mutation, the system automatically spins up a
localized Postgres clone using thin-cloning technologies or logical replication.
The system applies the agent's migration script to this clone and utilizes a
dedicated Data Validation Agent to execute millions of randomized read/write
operations against the mutated schema, ensuring no performance regressions or
data corruptions occur. Furthermore, the system strictly enforces the generation
of a mathematically verified "down" migration. If the "down" migration fails to
perfectly restore the original exact byte-state of the database clone, the Slice
is mechanically blocked. This capability completely immunizes the factory
against catastrophic data loss.

### **Workstream Beta: Multi-Agent Debate for Architectural Deadlocks**

When a high-level epic requires fundamental architectural decisions (e.g.,
choosing between an event-sourced ledger or a traditional relational table for a
new feature), relying on a single flagship model's zero-shot output introduces
massive systemic bias. The Multi-Agent Debate architecture introduces a
structured, supervised negotiation phase.  
The BEAM orchestrator spawns three distinct agents possessing deliberately
varied system prompts: one optimized for execution speed, one optimized for
database normalization, and one serving as a devil's advocate focused purely on
security constraints. These agents are forced into a multi-turn, text-based
debate, submitting their arguments into an Ash Framework consensus state
machine. The agents critique one another's proposed architectures until a
mathematical consensus is reached regarding the optimal path forward. The
resulting architecture is then compiled into the final Agent Brief and handed
off to the execution swarm.

### **Workstream Gamma: Just-in-Time Ephemeral Staging Environments**

A core limitation of differential testing is that it often relies on unit or
integration test layers, which may miss macroscopic deployment issues.
Leveraging container orchestration, Conveyor can be extended to generate
Just-in-Time Ephemeral Staging Environments.  
For every single Slice successfully traversing the epic gate, the system
automatically provisions an entirely isolated, fully functional stack—including
the application server, Postgres database, and mocked external APIs—mapped to a
unique ephemeral URL. A specialized End-to-End Evaluation Agent is then
dispatched to visually and programmatically interact with this deployed
environment, ensuring that the generated code functions perfectly in a true
production-like context before the merge to the main trunk is ever authorized.

### **Workstream Delta: Code-Scent Guided Context Compression**

As codebases scale into hundreds of thousands of lines, the token constraints of
LLM context windows become a severe bottleneck. While the Self-Training Context
Scout identifies which files are relevant, it still passes entire files to the
agent. Code-Scent Guided Context Compression utilizes the AST-parsing
capabilities of the BEAM to structurally compress the context window.  
Instead of sending full Elixir files, the system parses the dependency graph and
strips out the bodies of functions that are not strictly relevant to the current
task, retaining only their public signatures, typespecs, and docstrings. This
semantic compression allows the agent to understand the macro-architecture of
the entire application while utilizing only a fraction of the context window. By
aggressively compressing irrelevant execution logic, the factory drastically
lowers API expenditure while simultaneously minimizing the probability of the
agent suffering from "lost-in-the-middle" attention degradation.

## **Strategic Conclusion**

The exhaustive architectural blueprint detailed herein transcends the basic
automation of scripting workflows; it constructs a self-regulating, economically
optimized, and mathematically verifiable swarm intelligence running securely
atop the resilient BEAM platform. By adhering strictly to the
Determinism-Boundary Law, utilizing true Docker container isolation over fragile
state management, and meticulously implementing the prescribed Phase 1 data
schema seams, the seamless transition from a single-slice tracer bullet to a
highly concurrent autonomous factory is structurally guaranteed.  
The implementation of these advanced capabilities—spanning from the semantic
ingestion of contracts to the adversarial hardening of the verification
gate—synthesizes a system where operational context compounds automatically,
execution costs are rigorously governed by expected-value algorithms, and trunk
safety is mathematically enforced. The resulting Conveyor ecosystem will possess
the requisite antifragility to operate continuously and unattended, transforming
high-level human planning into deterministic, production-grade reality.

#### **Works cited**

1. BRAINSTORM.md
