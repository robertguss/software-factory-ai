# Conveyor — Living Strategy Doc

> Status: **brainstorming** (no implementation yet). This is the durable
> artifact for our thinking. We update it as decisions firm up. Nothing here is
> final until moved to the "Decided" section.
>
> **Name/lineage DECIDED:** project is **Conveyor**, the successor to _Conveyor
> AI_. Conveyor AI proved the core principle (deterministic core owns
> validation + recorded runs; agents own judgment) at CLI scale. Conveyor grows
> that into a full autonomous factory on the BEAM. (Repo/dir/remote rename from
> `software-factory-ai` is a separate mechanical step to do when ready — not
> done yet.)

## 1. Vision (one paragraph, will sharpen)

**Conveyor** is an AI-first software factory on the BEAM: the human does
research, brainstorming, and planning (externally, for v1), then hands a
finished hybrid plan to the factory, which decomposes it into a
dependency-ordered, contract-bearing work-graph and executes it with a fleet of
AI coding agents (Codex, Claude Code, Gemini CLI) in isolated containers, 24/7,
targeting 10+ concurrent agents. Work moves down the "conveyor" through
stations/gates; nothing advances until it passes its station. Built first for
Robert, then open-sourced. Explicit value: **simpler and better than the
agentic-coding-flywheel** by leveraging container isolation + a central BEAM
conductor to dissolve coordination complexity, and the verification gate as the
human's trusted stand-in. Lineage: successor to **Conveyor AI**.

## 1b. Inherited from Conveyor AI (fold in, don't redesign)

- **Recorded run (evidence dossier + manifest):** every bead attempt records a
  dossier (diffs, commands, test/gate output) = event-source + audit + eval
  dataset + the artifact reviewers judge.
- **`run check`:** deterministic half of the bead gate.
- **`review run`:** AI review judges the _recorded dossier_, not the live
  session → reproducible, replayable, auditable reviews. ADOPT WHOLESALE.
- **`ready-for-agent` states + Agent Brief:** bead lifecycle + the Brief packet
  (contract + context_pointers) handed to the implementer.
- **`blockedBy`:** graph edges.
- **"deterministic owns validation, agents own judgment":** = our
  determinism-boundary law (ratified). Conveyor AI is its proof of concept.
- **TODO:** mine existing Conveyor AI artifacts (CONTEXT, ROADMAP, ADR 0004,
  schemas, recorded-run-loop design) to reuse proven schemas/decisions rather
  than redo them.

## 2. Reference digest

### agentic-coding-flywheel (Jeffrey Emanuel) — what it actually is

A self-reinforcing ecosystem of ~10 bespoke tools:

- **Plan space**: multi-model planning (GPT Pro + Opus + Gemini) → synthesize
  "best of all worlds" → "100 ideas, show me 10" creativity passes. Plans reach
  3,000–6,000 lines before any code.
- **Beads (bd/br/bv)**: dependency-aware DAG issue tracker (Dolt-backed). Plan →
  200–500 beads with deps. `bv` does graph-theory routing to pick next ready
  bead.
- **Agent Mail (MCP)**: coordination layer. Targeted (not broadcast) messages,
  file reservations + advisory locks w/ TTL, whimsical disposable agent
  identities, thread IDs tied to bead IDs.
- **NTM (Named Tmux Manager)**: spawns/manages agent sessions in tmux panes.
- **DCG (Destructive Command Guard)**: mechanically blocks dangerous shell
  commands.
- **UBS**: mechanical bug/anti-pattern scanner. **CM/CASS**: memory + code
  search. **CAAM**: auth/account switching. **RU/rch**: remote build/test
  execution.
- **Hard stance**: _all agents commit directly to `main`, no git worktrees, no
  feature branches._ Conflicts handled by file reservations + pre-commit guard +
  DCG.
- **Human role**: "tend the swarm" — rescue stuck/compacted agents, send review
  prompts, check for stuck beads. (i.e. human-in-the-loop, NOT fully
  autonomous.)
- **Cost**: VPS $40–56/mo + Claude Max $200 × (1–5) + ChatGPT Pro $200 × (1–5) +
  Gemini $20. Up to ~$2,000+/mo at full swarm.
- **Claim**: 25 agents → 11,000 lines tested code, 204 commits, ~5 hours (CASS).

### Beads (gastownhall/beads)

Distributed graph issue tracker for agents, Dolt-backed. Hash IDs (`bd-a1b2`)
avoid merge collisions. `bd ready` (unblocked tasks), `bd update --claim`
(atomic claim), hierarchical epics (`bd-a3f8.1.1`), `bd remember` (project
memory), compaction (memory decay), messaging w/ threads. Stealth mode, git-free
mode, server mode (multi-writer). **This is a strong off-the-shelf core for the
task graph.**

### CodeScent (robertguss/code-scent-mcp) — Robert's own MCP

Local, MCP-first codebase-improvement server. Indexes repos locally, finds
deterministic code-health issues, bounded search/graph tools, reports, CI/diff
review, opt-in subjective review, loopback dashboard. **Safety: writes only
`.codescent/`, never edits source, no runtime network by default.** Python +
TS/React/Next packs. → Natural fit as the **quality/verification gate** in the
factory.

### Conveyor AI (Robert's prior, related project) — reuse the architecture

Prior decision (from memory): deterministic CLI owns validation, linking,
schemas, recorded run-state; external AI/human actors own judgment + generated
content. Minimize human involvement by orchestrating external agents only where
generation/ execution/review _judgment_ is needed. **This boundary is the right
backbone.**

## 3. My (agent) strongest opinions & pushback — see chat for full argument

- **The flywheel is NOT autonomous; it's human-tended.** "Fully autonomous 24/7"
  is a materially harder system. The crux is: _what closes the loop when an
  agent is stuck at 3am with no human?_ That answer reshapes everything.
- **"Everyone commits to main, no worktrees" is wrong for autonomous
  operation.** It works for an interactive babysitter. For 24/7 unattended, a
  broken commit poisons the trunk every other agent inherits. Counter-proposal:
  **isolated workspaces (worktrees/containers) + a merge queue gated on green
  CI.**
- **Isolation removes most of the need for a coordination layer.** Agent Mail /
  file reservations / advisory locks exist _because_ everyone shares one
  branch + filesystem. Give each agent an isolated worktree/container and only
  the merge queue touches `main`, and you can delete most of that complexity.
  (Directly challenges the flywheel's core AND simplifies, which is your stated
  goal.)
- **The real bottleneck is verification, not code generation.** 10 agents
  writing code is worthless without trust. Center of gravity = the verification
  gate (tests + CI + CodeScent), not the agent spawner.
- **~10 bespoke tools is the complexity you're complaining about.** Collapse
  into fewer composable primitives: (1) task graph, (2) isolated workspace, (3)
  verify gate, (4) dispatcher/scheduler, (5) observability/cost control.
- **Cost & marginal value.** Agents 6–10 have questionable marginal value and
  ~$2k/mo is a real adoption barrier for an OSS tool. Consider tiered model
  routing (cheap models for mechanical beads, expensive only for
  architecture/review).
- **Orchestrator = job scheduler, not a tmux cockpit.** Work queue + stateless
  containerized workers + dispatcher + merge gate scales horizontally and
  survives restarts; tmux panes don't.

## 4. Decided

- **Q1 — Autonomy boundary: TRULY AUTONOMOUS (self-healing).** Overnight the
  system self-heals (auto-retry, escalate to a supervisor agent, re-plan, or
  park the bead and move on). Human reviews a morning digest only.
  - _Agent caveat (accepted framing):_ autonomy is **earned and staged**, not
    day-one. Even at full autonomy there is a small "park for human judgment"
    queue for genuine product-judgment calls. North star = drive that queue → 0
    and ramp trust as the verification gate proves itself.
  - _Implication:_ the **verification gate is the human's stand-in.** It is the
    single most load-bearing component. Design the whole factory around it.

- **Q2 — Verification: TIERED PYRAMID scoped to change size.** Gate strength
  scales with scope; maps onto Beads epic→task→subtask hierarchy.
  - **Bead gate** (every task, fast/cheap): build + bead's own acceptance
    contract (specific behaviors + targeted tests that must exist & pass) +
    CodeScent health delta (no new smells) + quick reviewer-agent sanity pass.
  - **Epic gate** (feature complete, heavier): full suite + property-based
    tests + **mutation testing on epic's modules** + **adversarial red-team
    agent** + integration/e2e of the workflow + cross-cutting CodeScent scan.
  - **Phase/release gate** (rare, brutal): full mutation + e2e +
    perf/regression + security-review agent + dependency audit → morning digest
    to human.
  - **Principle — separation of duties:** the agent that writes code must NEVER
    write its own acceptance contract or red-team tests. Acceptance contracts
    are **locked during planning** (pre-code); red-team is a _different_ model.
    (Same boundary as Conveyor's "deterministic owns validation".)

## 5. Open questions (working stack, one at a time)

1. ~~Autonomy boundary~~ → DECIDED (truly autonomous, staged).
2. ~~Verification gate~~ → DECIDED (tiered pyramid + separation of duties).
3. ~~Integration/isolation model~~ → DECIDED (isolated container per agent +
   merge queue + frequent integration to `dev`; `main` protected, promoted at
   phase gate).
4. ~~Orchestration substrate~~ → DECIDED: **BEAM/Elixir conductor, raw OTP +
   Oban** (not Jido yet). Best-fit runtime for 24/7 self-healing supervision of
   many concurrent processes; "best machine for the job" weighted over OSS
   adoption.
5. ~~Work-graph store~~ → DECIDED: **native Ash/Postgres, drop Beads.**
   All-Elixir, single coherent stack. Steal Beads' ideas (hash IDs, auto-ready,
   compaction). "Best machine for the job" explicitly weighted over scope/time.
6. **Planning → contract pipeline** — DESIGN IN PROGRESS (see section below).
   Open sub-fork: human involvement depth in planning. (active) 6b. ~~Human
   involvement depth~~ → DECIDED: **#1 intent author + epic-level approver**,
   evolve toward risk-tiered (#4) as trust grows. 6c. ~~Planning location~~ →
   DECIDED: **multi-model planning ritual is EXTERNAL/manual for v1.** Factory
   input = a finished hybrid plan. Factory scope v1 = ingest → decompose →
   contracts → execute. (Pull planning in later = just more agents.) 6d.
   ~~Testing/TDD~~ → DECIDED design: **Test Architect role** (plan-phase agent,
   separate from implementer + critic) authors
   `required_tests`/properties/thresholds into the contract. **Trustworthy
   agent-TDD:** Red=Test Architect, Green=implementer, Refactor=CodeScent; Ash
   policy enforces `test-author ≠ implementer` and contract is read-only to
   implementer. Kills the "weak code + weak self-test" failure. 6e.
   ~~Implementation prescription~~ → DECIDED: contracts own the WHAT (intent,
   interface, acceptance, tests, verification); leave HOW to the implementer
   EXCEPT genuine architectural constraints, which become explicit "design
   beads" with their own contract. 6f. **Factory evaluation layer** (distinct
   from code verification): bead success rate, gate false-negative rate,
   cost/bead, model-vs-bead-type win rates, recurring failure modes,
   time-to-green — powered by the event-sourced log; feeds institutional memory.
   This is the true compounding flywheel. (ratified concept) NAME. ~~Project
   name / lineage~~ → DECIDED: **Conveyor**, successor to Conveyor AI; fold in
   its recorded-run / deterministic-validation / AI-review ideas.
7. **Orchestration layer (the deferred Phase 4 heart)**: single-run loop → MANY
   parallel supervised runs (Context Scout + implementer + reviewer
   spawn/supervise/ gate/merge). (highest net-new value)
8. Verification engine internals (red-team, mutation, drift detector, circuit
   breakers, shadow mode).
9. Self-healing mechanics (retry budgets, supervisor agent, re-plan/park
   criteria).
10. Dispatcher scoring algorithm (which slice, which model, which budget).
11. Economic governor (cost ledger, budget-aware scheduling, runaway
    kill-switch).
12. Institutional memory (structured Memory + pgvector recall; Conveyor AI Phase
    3).
13. Multi-account / rate-limit credential pool (the CAAM idea).
14. Artifact storage: repo-native markdown/JSON `.conveyor/` vs Ash/Postgres vs
    BOTH (Postgres=runtime truth; materialize repo-native projections). (queued)

## Principle: steal IDEAS, reuse boring INFRA

Reimplement in Elixir the _logic_ (work-graph, gate orchestration, dispatch
routing, memory). Do NOT reimplement the _infra_ (Docker, git, PTYs, the coding
CLIs) — drive those. BEAM = brain; it orchestrates boring battle-tested hands.

## Flywheel → Elixir-native mapping

- Beads → Ash + `ash_state_machine`.
- Agent Mail → mostly DELETED (central conductor is the coordinator; no
  peer-to-peer); keep only a per-bead event log.
- `bv` routing → dispatcher scoring fn (priority × critical-path × unblock-count
  × model-fit).
- NTM/tmux → DynamicSupervisor + containers (herdr optional human cockpit only).
- DCG → container isolation + thin exec-guard module.
- UBS → CodeScent as a gate stage.
- CM/CASS → Ash + pgvector institutional memory; agents bring own code search.
- CAAM → GenServer credential pool, rate-limit-aware checkout.
- RU/rch → Oban jobs + BEAM distribution (gates on other nodes).

## Agent's candidate principles / original ideas (not yet ratified)

1. **Event-sourced work-graph** — immutable transition log → time-travel
   debugging, audit, replay. (Generalizes Conveyor recorded-run-state.)
2. **Acceptance contracts = first-class, immutable-to-implementer.** Authored at
   plan time by a different actor; implementer gets read-only. Ash policies
   enforce author ≠ contract-author ≠ red-team. **Output quality is hard-capped
   by contract quality** → invest most here.
3. **Economic governor** — cost ledger as Ash resource; budget-aware graceful
   degradation (fewer agents / cheaper models); auto-kill runaway loops. Cost is
   a scheduling input, not a report.
4. **Institutional memory that compounds** — pgvector recall of what passes
   gates / recurring failure modes, injected into future agent context. The real
   "flywheel."
5. **Determinism boundary as law** — all _decisions_ (ready/blocked, merge,
   park/retry) are deterministic Elixir; only _agents_ are stochastic; LLM
   verdicts are recorded and themselves gate-checked.
6. **BEAM distribution (libcluster)** = horizontal scale for "10+ agents" for
   free.
7. **Anti-death-spiral (earned autonomy)** — shadow mode + measure gate
   false-negative rate; circuit breakers (halt epic after N gate failures);
   drift detector (re-validate whole `dev` vs original plan/contracts). Autonomy
   is a dial turned up as the gate proves itself.
8. **Reproducible agent envs** — pinned devcontainer/Nix image shared by agents
   AND gates, so "passes in agent, fails in gate" can't happen.

## Planning → contract pipeline (design)

**Shape:** IDEA → PROSE PLAN (human + multi-model synthesis ritual) →
DECOMPOSITION (spec agent: plan→epics→beads+draft contracts) → ADVERSARIAL
CONTRACT REVIEW (critic agent) → COMPLETENESS GATE (deterministic; no contract =
not ready) → READY POOL.

- Prose plan = **constitution** (source of intent, human-readable). Work-graph =
  executable projection. Linked + event-sourced → controlled **plan-amendment**
  flow when reality diverges (no silent drift).
- **KILLER INSIGHT — contracts lock the INTERFACE, not just behavior.** Freezing
  each bead's public API/types/signatures at plan time lets dependent beads be
  built in parallel against stubs _before deps finish_, and makes the flywheel's
  "logical merge conflict" class disappear by construction. Contract =
  verification target AND coordination mechanism. This is what truly justifies
  isolation + 10+ parallelism.
- **Acceptance contract fields (Ash resource):** intent; interface (locked);
  behavioral_assertions (Given/When/Then); required_tests (authored by spec/test
  agent, NOT implementer); properties (StreamData); codescent_thresholds;
  non_goals; dependencies; context_pointers; done_definition (deterministic
  close check).
- **Bead-sizing principle:** if you can't write a crisp machine-checkable
  contract for it, it's too big/vague — split. Contract-authorability = the
  sizing test. Target = "one agent, one session, one PR, independently
  verifiable." Mechanically kills the flywheel's vague-bead failure (vague beads
  fail the completeness gate).

## Human/Machine contract (DECIDED) + handoff checkpoint

- **No dependency on Conveyor AI Go CLI.** Mine ideas/schemas/taxonomy only.
  Conveyor is a ground-up Elixir next-level system: Conveyor AI
  prepared/recorded ONE human-launched run; Conveyor autonomously orchestrates a
  supervised FLEET.
- **Contract:** YOU own research→brainstorm→multi-model planning→ONE finished
  hybrid plan (prose). Handoff = the plan doc. CONVEYOR owns
  ingest→decompose→draft Briefs+contracts→ scout→readiness gate→run agents in
  parallel→record evidence→review→verify→merge→learn→ morning digest +
  parked-items queue.
- **Handoff checkpoint DECIDED:** ONE approval gate. Conveyor decomposes → shows
  epic/slice breakdown + draft Briefs → human approves/tweaks → THEN autonomous
  execution. (Evolve to risk-tiered auto-approval as trust grows.)

## Orchestration layer design (Q7 — the deferred Phase 4 heart)

### Slice journey (conveyor stations; Ash state machine, event-sourced)

drafted → approved (human epic gate) → ready (deps satisfied + readiness gate) →
scouting (Context Scout → Context Pack) → prompt_built (versioned Run Prompt) →
implementing (agent in isolated container, heartbeat) → evidence_recorded
(dossier+ledger; deterministic run-check) → slice_gate (deterministic checks +
reviewer-on-dossier) → integrating (auto-PR → merge queue re-runs gate vs latest
dev → merge) → done. Off-ramps: needs_rework (retry w/ feedback), parked (human
queue), failed. Epic gate fires when all epic slices done-on-dev; phase gate
promotes dev→main.

### OTP + Oban topology

- **Transient coordinators = GenServers** (rebuild from Postgres on restart):
  `Conductor` (top supervisor), `Dispatcher` (watches ready pool, concurrency
  cap N, scores+claims), `MergeQueue` (serializes dev integration), `Governor`
  (budget/cost).
- **Per-slice work = Ash state + Oban jobs** (NOT a long-lived GenServer per
  slice). Each long step (scout/implement/gate) = a durable Oban job → survives
  reboot, retries, idempotent regeneration (mirrors Conveyor AI idempotent run
  record). SliceRun = the state machine advanced by job completions.
- **CRASH RECOVERY = SELF-HEALING (recommended, treat as decided unless
  objected):** because slice state lives in Ash/Postgres and runs are
  event-sourced, a crashed job/ reboot resumes from last durable state. Watchdog
  Oban job detects stuck slices (heartbeat / no git+gate progress within
  timeout) → retry/escalate/park.
- `WorkerPool` manages container spawn/teardown; `CredentialPool` GenServer
  hands out API accounts/keys with rate-limit-aware checkout (the CAAM idea).

## Conveyor AI mined — ADOPT this proven design (intellectual honesty: much of

## my "original ideas" were already here)

**Reframe:** Conveyor (factory) = **Conveyor AI's deferred Phase 4.** Conveyor
AI explicitly scoped Phase 1=prepare, Phase 2=record+review, Phase 3=learn, and
repeatedly deferred _implementation-agent orchestration_ to "a later phase."
THIS project is that phase: the proven single-run loop, ported to Elixir/Ash,
plus orchestration + parallelism + isolation + verification rigor + autonomous
self-healing. ADR 0004's "deterministic CLI owns validation, AI owns judgment" →
"deterministic BEAM conductor owns validation."

**NOTE:** Conveyor AI is Go + markdown-first artifacts. We PORT the
design/schemas/ domain-language/taxonomy to Elixir/Ash; we do not reuse the Go
code.

### Adopted domain language (replaces my ad-hoc terms; "Slice" replaces "bead")

- **Intent** → **Plan** → **Slice** (narrow vertical independently-verifiable
  unit).
- **Agent Brief** = the durable CONTRACT for a slice: current/desired behavior,
  acceptance criteria, **key interfaces** (NO file paths — they go stale;
  behavioral not procedural), out-of-scope, risk. _(This validates BOTH my "lock
  the interface" insight AND my "contracts own WHAT not HOW" pushback — Conveyor
  AI already codified exactly this in the triage AGENT-BRIEF skill.)_
- **Context Scout → Context Pack** — read-only (possibly agentic) pass that
  prepares a CITED map (files+why, interfaces, ADRs, memories, risks,
  confidence) BEFORE the implementer runs. Separates discovery from execution.
  _(Upgrade to my weak `context_pointers` field — adopt as a real subsystem.)_
- **Run Prompt** — GENERATED, VERSIONED prompt (Brief + Pack + Memory + Policy +
  output contract). Versioned templates: `implementation-prompt@x`,
  `context-scout@x`, `reviewer@x`, `memory-selector@x` → enables outcome
  comparison / optimization.
- **Agent Run → Evidence → Run Dossier (human) → Run Ledger (machine)**.
- **Review** — external agent owns verdict; CLI/conductor records+validates.
  Runs on the RECORDED dossier, not the live session → reproducible.
- **Memory** (structured: evidence/scope/confidence/status) + **Policy**
  (enforceable rule).

### The proven Core Loop (adopt)

Intent → Plan → Slices → Agent Brief → Context Scout → Context Pack → Readiness
Gate → Run Prompt → Agent Run → Evidence → Run Dossier → Review → Memory
Candidates → Next Run.

- **Readiness Gate statuses:** ready / needs-clarification / needs-context /
  too-large / blocked. (= my completeness gate; "too-large" = my
  contract-authorability sizing test.)

### Failure Taxonomy (THE eval engine — makes "agent failed" actionable)

Brief Failure · Context-Pack Miss · Execution Failure · Validation Failure ·
Review Failure · Memory Failure · Policy Failure. Each tells you WHICH station
to fix. Feeds Run Ledger → DSPy/GEPA optimization loop (metrics:
first-pass-success, AC-pass-rate, context-pack-miss-rate,
token-cost-per-success, repeat-mistake-rate, rework-rounds).

### Run Ledger manifest schema (reuse, port to Ash)

id, status, outcome, briefId, contextPackId, runPromptId, risk, agent, model,
baseCommit, headCommit, workspaceState, readiness{decision,warnings,blockers,
humanApprovalStatus}, startedAt, completedAt, changedFiles[],
commands[{cmd,status, evidence}],
acceptanceCriteria[{text,status∈passed/failed/skipped/missing,reason?,
evidence[]}], counts{},
review{status,reviewer,decision∈accepted/needs-rework/rejected,
recommendation∈merge/rework/ask-human/archive,findings[{severity∈blocking/warning/note}],
checks}, memoryCandidates[].

### What the factory NET-NEW adds (honestly scoped, after subtracting Conveyor AI)

- Container isolation that dissolves coordination + merge queue (dev→main).
- Tiered verification PYRAMID (slice→epic→phase) w/ adversarial red-team +
  mutation + property testing (Conveyor AI had Review; not scope-tiered gate
  rigor).
- BEAM/OTP autonomous self-healing control plane (Conveyor AI was human-launched
  single-run).
- Economic governor, drift detector, circuit breakers, shadow-mode.
- BEAM distribution for horizontal scale.

## Target subsystem map (~8 subsystems vs flywheel's ~10 tools)

PLANNING → WORK-GRAPH+CONTRACTS (Ash, event-sourced) → DISPATCHER (scoring) →
WORKER POOL (DynamicSupervisor → containers → coding CLIs) → VERIFICATION
PYRAMID (bead→epic→phase) → MERGE QUEUE → dev → (phase gate) → main.
Cross-cutting: OBSERVABILITY/CONTROL (LiveView + digest + parked queue),
ECONOMIC GOVERNOR, INSTITUTIONAL MEMORY (pgvector).

## Decided detail — Q4 Substrate + Elixir stack layering

- **Conductor = BEAM/OTP + Oban.** DynamicSupervisor over worker processes; Oban
  = durable scheduled jobs (survives reboot, retries, cron); GenServers for
  dispatcher, merge-queue, gate-runners. Start raw OTP; graduate to Jido only if
  we build many _native in-BEAM reasoning agents_.
- **Self-healing = literal OTP supervision** (`:transient` restart,
  max_restarts/ max_seconds, escalation up the tree). The flywheel's hand-rolled
  "fountain-code resilience" is native here.
- **Phoenix/LiveView = YES (unambiguous).** Real-time dashboard, morning digest,
  parked-bead triage, cost meters, bead-graph viz. Phoenix PubSub fans out
  events.
- **Ash = probably YES.** `ash_state_machine` (bead lifecycle w/ guarded
  transitions), `AshOban` (durable job glue), Ash policies (mechanically enforce
  Q2 separation-of-duties: reviewer/red-team actor ≠ author actor), AshPostgres
  (one datastore), AshAdmin (free admin UI). Cost: steep learning curve.
- **Layers:** Brain = OTP+Oban. Domain/State = Ash+Postgres.
  Observability/Control = Phoenix LiveView. Hands = containers running coding
  CLIs (Claude Code/Codex).
- **herdr / tmux = OPTIONAL operator cockpit, NOT in the control loop.**
  Autonomous path runs headless (containerized CLI + stdout + heartbeat).
  herdr's real value = human attach/intervene on _parked_ beads (SSH/mobile drop
  into a live agent session). Do NOT couple self-healing/stuck-detection to
  herdr's TUI parsing; derive "stuck" from our own signals (heartbeat, no
  git/gate progress within timeout).

## Decided detail — Q3 Integration/isolation

- **Isolated container per agent.** Containers (over worktrees) chosen for:
  blast-radius sandboxing of destructive commands (shrinks DCG to "container
  can't touch host"), reproducible per-agent env, clean teardown.
- **Flow:** bead passes bead-gate in its container → auto-PR → **merge queue**
  re-runs gate against latest → merges into `dev` integration branch. Epic gate
  runs on `dev`. `main` is protected; promoted only when phase gate passes.
- **Eliminated by this choice:** Agent Mail, file reservations, advisory locks
  (3 of the flywheel's ~10 tools). Frequent small-bead integration avoids the
  long-lived-divergent-branch logical-conflict problem the flywheel warned
  about.

## 6. Phased implementation roadmap (DRAFT — react/adjust)

**Q8 v1 LINE DECIDED:** v1 = **Phase 1 thin tracer bullet** (one Slice
end-to-end, human-in-loop, manual merge). Phases 2–8 = roadmap to the dream.
Learn whether the loop _feels_ right on real slices before scaling.

**RATIFIED PRINCIPLE — front-load gate validation.** The riskiest assumption in
the whole design is that the verification gate can be made strong enough to
trust unattended. So we validate the gate's honesty in **Phase 1**, not later: a
**gate-canary harness** runs a labeled set of injected-bug "mutants" through the
gate-only and asserts each is REJECTED, tracking the false-negative rate
(smallest instance of Phase-5 shadow mode). A gate that passes a mutant = a
release-blocking Conveyor bug. If the gate can't be trusted, "autonomous" just
means "fast at being wrong."

**Phase 0/1 clarifying decisions (see
`docs/PHASE-0-1-IMPLEMENTATION-PLAN.md`):**

- Tracer target = a sterile, disposable **sample FastAPI (Python)** repo.
- First implementer = **Pi** (`pi.dev`) over **RPC/JSON via a BEAM Port**,
  OpenAI/Codex provider, behind a thin `AgentRunner` adapter (Cursor CLI / Codex
  / Claude Code later). Pi's minimalism keeps orchestration in the conductor;
  CodeScent stays a conductor-run gate stage (Pi's "no MCP" is irrelevant — the
  implementer never calls it).
- Isolation = **single Docker container from day one** (carries into Phase 3
  WorkerPool).
- In Phase 1 the human hand-authors the single Plan/Epic/Slice/Brief AND the
  failing tests (acting as Test Architect); the conductor independently re-runs
  the gate.
- New doc `docs/PHASE-0-1-IMPLEMENTATION-PLAN.md` = comprehensive standalone
  plan for multi-model comparison + hybrid synthesis.

- **Q7b parallelism DECIDED:** phased — strict `blockedBy` deps for v1;
  interface-stub parallelism deferred to v2 (Phase 8).
- **Phase 0 — Foundations.** Elixir+Phoenix+Ash+Oban+Postgres skeleton. Core Ash
  resources (Plan, Epic, Slice, AgentBrief, ContextPack, RunPrompt, AgentRun,
  Evidence, Review, Memory, Policy), event-sourced ledger, Slice
  `ash_state_machine`. Deterministic core, no agents.
- **Phase 1 — Single-Slice tracer bullet (MVP).** One Slice end-to-end,
  human-in-loop: readiness → Context Scout → Run Prompt → one implementer in
  container → Evidence (dossier+ledger) → deterministic run-check →
  reviewer-on-dossier → manual merge.
- **Phase 2 — Decomposition + approval gate.** Spec agent:
  plan→epics/slices/Briefs → critic review → human epic-approval checkpoint →
  ready pool.
- **Phase 3 — Parallel fleet + merge queue.** Dispatcher + cap N + WorkerPool +
  isolated containers + merge queue → dev. Strict deps. CredentialPool.
- **Phase 4 — Verification pyramid.** Slice gate (CodeScent+tests), epic gate
  (mutation+ property+red-team), phase gate. Ash-policy separation-of-duties.
- **Phase 5 — Autonomy + self-healing.** Watchdog, retry budgets, supervisor
  agent, re-plan/park, circuit breakers, drift detector, shadow-mode → autonomy
  dial.
- **Phase 6 — Economic governor + observability.** Cost ledger, budget-aware
  scheduling, runaway kill-switch, LiveView digest + parked-queue triage.
- **Phase 7 — Learning loop.** Structured Memory + pgvector recall into Run
  Prompts; failure-taxonomy analytics; DSPy/GEPA prompt-template optimization.
- **Phase 8 — Throughput upgrades.** Interface-stub parallelism + BEAM
  distribution.
