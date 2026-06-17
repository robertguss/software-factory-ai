# Conveyor Vision

Conveyor is an AI-first software factory on the Elixir/BEAM. A human does
research, brainstorming, taste, architecture, and final intent authoring, then
hands Conveyor a high-quality plan. Conveyor turns that plan into a
dependency-ordered, contract-bearing work graph and runs AI coding agents in
isolated containers, recording every attempt as immutable evidence, gating the
output through deterministic verification and external review, and learning from
the results. It is the BEAM-native successor to Conveyor AI, a Go CLI that
proved the single-run loop.

The guiding bets are:

- isolation over coordination;
- the verification gate is the human's stand-in;
- agents produce bounded execution, not authority;
- the deterministic conductor owns truth while stochastic agents own generation
  and judgment.

## Product Contract

The first public promise is:

> Conveyor converts a human-approved plan into coordinated, verified
> implementation work packets, with evidence strong enough to support pull
> requests and eventually low-risk auto-merge.

Conveyor does not initially promise fully autonomous software development, agents
coding and deploying around the clock, or broad deployment authority. The
long-term vision can be true autonomy, but the implementation path must earn
authority through measured trust.

## Autonomy Line

Autonomy is a policy dial, not a marketing claim.

| Level | Name | Authority allowed |
| ---: | --- | --- |
| L0 | Planning only | Audit plans, draft Slices, identify risks, and propose tests. No code edits. |
| L1 | Local implementation | Produce diffs in isolated workspaces or containers. No PR creation. |
| L2 | PR generation | Create PR-ready evidence packets and draft PR bodies. Human merge. |
| L3 | Auto-merge low-risk | Auto-merge only low-risk, green, well-scoped Slices through the merge queue. |
| L4 | Auto-deploy | Deploy only after repo-specific trust, phase gates, and explicit release policy. |

Phase 1 target: **L1 with L2-shaped artifacts**. The run produces a PR-quality
evidence packet and PR-body draft, but merge remains an external manual human
action. Conveyor may record the human's integration decision and resulting
commit, but it does not merge by default in Phase 1.

## Design Laws

These laws are invariants to test, not aspirational prose.

1. **No task without acceptance criteria.** A Slice that cannot be verified is
   too vague or too large.
2. **No implementation without a locked contract.** The implementer may not
   weaken or edit acceptance tests, required tests, risk policy, or done
   definition.
3. **No completion without evidence.** Agent self-report is not evidence. The
   conductor independently records evidence.
4. **No authority without measured trust.** Autonomy level increases only after
   the gate's false-negative rate, review outcomes, and rollback or bug metrics
   justify it.
5. **No hidden state.** Every material transition and gate result appends a
   `LedgerEvent`.
6. **No shared-trunk chaos.** Phase 1 uses one isolated container. Later phases
   use one task, one workspace/container, one evidence packet, and a merge
   queue.
7. **No source mutation by context tools.** CodeScent and scouts may write their
   own cache or `.codescent/` state, but they do not edit source.
8. **No dangerous commands by default.** Docker constrains blast radius;
   `ExecPolicy` constrains intent.
9. **No orphan requirements and no orphan Slices.** Requirements map forward to
   Slices; Slices map back to requirements, decisions, bugs, or explicit
   improvements.
10. **No bespoke tool empire.** Conveyor should build the conductor and evidence
    loop. Existing agents, git, Docker, CodeScent, linters, test runners, and CI
    do the routine work.

## Phase 0/1 Goals

- Stand up the deterministic Elixir core: Ash/Postgres domain, append-only
  ledger, durable Oban jobs, policy resources, and Slice lifecycle.
- Establish the factory kernel surface: config, doctor checks, plan audit,
  project instructions, policies, evidence exports, adapters, and gate honesty.
- Run one Slice end-to-end through plan audit, readiness, context scout, prompt
  building, policy-bounded implementation, evidence, RunCheck, review, gate,
  manual merge, and retrospective.
- Prove the gate can be made honest through a gate-canary harness that measures
  false negatives early.
- Prove trustworthy agent-TDD with locked acceptance tests authored outside the
  implementer and independently re-run by the conductor.
- Establish an `AgentRunner` adapter so Pi can later be swapped for other agent
  CLIs without changing the conductor core.
- Make requirement-to-Slice traceability real in miniature.
- Produce durable evidence packets and a human-readable dossier good enough to
  attach to a later PR.

## Explicit Non-Goals

- No new issue tracker.
- No chat system.
- No LLM framework.
- No static analyzer.
- No deployment platform.
- No parallel Dispatcher or WorkerPool fleet in Phase 1.
- No fully automated decomposition or multi-model planning in Phase 1.
- No merge queue in Phase 1.
- No autonomous self-healing, economic governor, institutional memory, or agent
  reputation routing in Phase 1.
- No interface-stub parallelism in Phase 1.
- No auto-deploy.
- No broad multi-repo orchestration.

Conveyor should orchestrate boring infrastructure and integrate tools. It should
not recreate the whole software ecosystem.
