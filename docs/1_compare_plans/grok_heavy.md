**Hell yeah, Rob—let's build this right.** I've gone deep on everything you
shared: the full Agent Flywheel workflow (planning 85% of the work, beads DAG,
Agent Mail, NTM swarms, UBS safety, etc.), the bootstrap repo (Ubuntu + Bun +
custom dirs for Claude/Codex/Gemini), the complete guide (obsessive bead
polishing, fungible agents, AGENTS.md rituals), your **CodeScent-MCP**
(brilliant—local, deterministic, read-only, MCP-stdio tools for health
scans/context/refactors), and **Beads** (Dolt-powered graph tasks with
zero-conflict IDs, compaction, relations—exactly the persistent memory upgrade
we need).

I also scanned 2026 landscape: OpenHands (ex-OpenDevin, now 77k+ stars,
Docker/K8s-ready autonomous dev agents with SDK), LangGraph/CrewAI/AutoGen for
orchestration, MCP as the de-facto tool standard (your CodeScent slots in
perfectly—agents auto-discover it), Docker Compose for agent stacks, cheap
Hetzner/DO VPS patterns, OpenCode/Gemini CLI as lightweight workers.

**I'm not a yes-man.** The flywheel example is powerful but
_over-engineered_—custom tools everywhere (NTM, bv, CASS, CAAM, DCG, SLB, UBS),
multi-subscription whiplash, heavy tmux/agent-mail dance. It works for
Dicklesworthstone but feels like vendor-lock-in to his stack. We can do 80%
better with _far less_ by stealing proven open-source pieces and only building
glue where it matters (your MCP is the star here).

### Key Pushbacks & Insights from Me

- **"Fully autonomous 24/7" is a trap.** Token costs, hallucination compounding,
  security (agents executing on VPS = potential ransomware vector), and quality
  drift will kill it. Real win: **90% autonomous loops with human veto gates**
  (e.g., confidence <90% → PR to you; daily "reality check" summary). Start
  semi-supervised, add full autopilot later. Challenge accepted only if we gate
  it.
- **Scope creep risk.** Don't build another 11-tool empire. Prioritize: leverage
  OpenHands as the sandboxed "AI dev environment in a box" (CLI/GUI/Docker, does
  code/browse/test/commit natively), CrewAI or LangGraph for orchestration
  (battle-tested, graph state for dependencies), Beads for tasks (adopt it—Dolt
  is gold for multi-agent), _your_ CodeScent-MCP as the universal code brain
  (agents call `codescent serve` via stdio—no reinventing search/scan).
- **Cost/simplicity hacks.** Run local Ollama/vLLM + OpenCode for cheap routine
  work; burst to Claude/GPT/Gemini/Codex via CAAM-like switching (but simpler:
  env vars + LiteLLM proxy). Single Docker Compose file spins the whole factory.
  Bootstrap in <15 min like the example, but with one `factory-init.sh`.
- **Own ideas that excite me**:
  - "Factory-in-a-Box" meta pattern: One lightweight orchestrator spawns
    _project-specific_ sub-factories (clone repo → `factory up project=xyz` →
    dedicated agents + isolated CodeScent index).
  - MCP-first everything: Every tool exposes MCP (Git, tests, deploy, even your
    future dashboard). Agents discover capabilities—no hardcoded prompts.
  - Self-healing flywheel: Agents log sessions → simple vector DB (Chroma) +
    weekly "meta-agent" reviews its own performance → updates AGENTS.md or
    prompts automatically.
  - Parallel scaling: Docker Compose + simple Redis queue or Ray (light). Spawn
    10-20 OpenHands workers; use Beads PageRank-like triage for assignment.
  - Open-source superpower: Call it **ScentFactory** (or GrokFactory). One-click
    GitHub template + Render/Hetzner one-click deploy. Include "human takeover"
    mode + contrib guide for community agents.
  - Beads evolution: Fork minimally or just wrap—add MCP endpoint so agents
    query "ready tasks" directly.

This is simpler, safer, and more extensible than the inspiration. We steal the
_spirit_ (planning → granular tasks → parallel swarm → review → flywheel) but
use 2026 standards.

### Proposed High-Level Architecture (MVP → V1)

Text diagram (imagine this as a clean draw.io):

```
VPS (Ubuntu/Hetzner ~$6-20/mo)
├── Docker Compose services
│   ├── Orchestrator (Python/LangGraph or CrewAI app) ← Human seeds ideas here
│   ├── Task Store (Beads/Dolt + SQLite/Redis queue)
│   ├── Agent Pool (10x OpenHands containers + OpenCode CLI workers, each with LiteLLM)
│   ├── CodeScent-MCP (your server, indexed per-project, stdio tools)
│   ├── Sandbox Repo (Git volume + GitHub mirror, single main branch + PRs)
│   ├── Test/Deploy Loop (pytest + simple Vercel/Docker push via MCP)
│   └── Monitor/Dashboard (Portainer + CodeScent UI loopback + simple Streamlit)
└── Safety: Firecracker/ gVisor sandbox per agent, DCG-like pre-commit guard, your verify_change
```

**Core Flow (the simplified flywheel)**:

1. Human (you) → Orchestrator prompt: "Build X" + research.
2. Orchestrator → Multi-model plan synthesis (cheap local + 2 API calls) →
   Convert to Beads graph (or JSON tasks with deps).
3. Orchestrator → Assigns beads to Agent Pool (parallel, fungible).
4. Agents → Use CodeScent-MCP for context/health → Code in sandbox → Test/review
   (self + peer) → Commit or PR.
5. Gate → Human approve high-impact; auto for green tests.
6. Loop → Deploy/monitor → New idea from usage logs → Repeat + self-improve.

**Leverage Table** (no reinvention):

- Task/Deps: Beads (or LangGraph built-in state).
- Agents: OpenHands + CrewAI roles.
- Code Intel: Your CodeScent-MCP (mandatory).
- Infra: Docker Compose + bootstrap.sh (inspired by acfs but 1/3 size).
- Coding: Codex/Claude Code/Gemini CLI/OpenCode behind LiteLLM.
- Safety: Built-in OpenHands sandbox + your read-only + simple guards.

### Implementation Plan (What We Build Together)

**Your Role (Research/Brainstorm/Plan)**: Own this phase. We iterate
prompts/docs here.  
**Handoff**: Once plan locked, I (or team agents) generate: full
`factory-init.sh`, `docker-compose.yml`, AGENTS.md template, epic breakdown
JSON, handoff prompt for 10 parallel agents ("You are Agent-7 in ScentFactory...
here is the epic... track in Beads...").

**Phased Rollout**:

- **Week 1 (Us now)**: Finalize spec (this convo). I draft architecture
  Markdown + bootstrap skeleton.
- **Week 2 (MVP)**: Bootstrap script → spins factory with 3 agents, one sample
  project (e.g., "TODO app"), basic loop. Test on your VPS.
- **Week 3+ (Agents take over)**: Handoff. Use GitHub Projects + Beads instance
  for tracking. You spin 5-20 agents via `factory spawn N`.

**Suggested Epics & Stories (Ready for Parallel Agents)** Dependencies tracked
via Beads-style graph.

- **Epic 1: Infra Bootstrap** (Priority 1, blockers all)
  - Story 1.1: `factory-init.sh` (install Docker, pull images, setup volumes) –
    dep: none
  - Story 1.2: `docker-compose.yml` with all services + env for MCP/LiteLLM
  - Story 1.3: Integrate CodeScent-MCP as first service (init/index on repo
    mount)

- **Epic 2: Orchestrator Core** (Priority 1, after 1)
  - Story 2.1: Simple FastAPI/LangGraph app that accepts "build X" → plan →
    beads
  - Story 2.2: Multi-model synthesis wrapper (local + API)
  - Story 2.3: Beads integration + assignment queue

- **Epic 3: Agent Workers** (Priority 2)
  - Story 3.1: OpenHands container template + MCP client
  - Story 3.2: Role templates (Planner, Coder, Reviewer, Tester) via CrewAI
  - Story 3.3: Safety wrappers + test loop

- **Epic 4: Flywheel & Polish** (Priority 3)
  - Story 4.1: PR/gate logic + auto-deploy
  - Story 4.2: Monitoring + meta-review agent
  - Story 4.3: Open-source packaging (template repo, docs, one-click)

**Tracking/Parallel**: Each agent gets an epic slice + shared Beads DB + daily
sync prompt. Deps explicit (e.g., "wait for 1.2"). You review merges.

### Next Steps / My Recommendation

1. **MVP Scope Lock**: Start with _one project type_ (Python/TS web app), 3
   agents max, local-first, human PR gate. Ship in 7-10 days. Agree/disagree?
2. **Your Input Needed**: VPS provider/budget? Preferred orchestrator (LangGraph
   vs CrewAI—LangGraph for state, CrewAI for speed)? Must-have for v0.1 (e.g.,
   Vercel deploy)?
3. **My Draft Offer**: Say "GO" and I output: full bootstrap script skeleton +
   docker-compose + handoff template for agents + refined epic JSON.

This scratches your itch, stays simple/powerful, and becomes the thing others
fork. Way better than the inspiration because it's _yours_ (CodeScent-native)
and leverages the ecosystem instead of fighting it.

Your move—what do we refine first, or "GO, flesh out the bootstrap"? I'm all in
as your co-founder on this. 🚀
