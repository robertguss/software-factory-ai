# Conveyor Autonomy Levels

Conveyor treats autonomy as a policy dial, not a promise of unchecked agent
authority. The dial can move only when evidence proves that the gate, sandbox,
adapter, reviewer separation, and project policy are trustworthy at the next
level.

## Level Contract

| Level | Name | Authority allowed | Merge and deploy authority |
| ----: | ---- | ----------------- | -------------------------- |
| L0 | Planning only | Audit plans, draft Slices, identify risks, propose tests, and produce implementation guidance. No code edits. | No merge. No deploy. |
| L1 | Local implementation | Produce diffs in isolated workspaces or containers, run local verification, and emit evidence packets. No PR creation by default. | No merge. No deploy. |
| L2 | PR generation | Produce PR-ready evidence packets and draft PR bodies. The system may prepare a PR proposal only under project policy. | Human merge only. No deploy. |
| L3 | Auto-merge low-risk | Auto-merge only low-risk, green, well-scoped Slices through the configured merge queue after gate, reviewer, and canary requirements pass. | Low-risk auto-merge only. Deploy remains separately gated. |
| L4 | Auto-deploy | Deploy only after repo-specific trust, phase gates, release policy, rollback checks, and explicit deployment authority are satisfied. | Merge and deploy authority are policy-gated and revocable. |

## Phase 1 Target

Phase 1 targets **L1 with L2-shaped artifacts**. A run may create a local diff,
independent verification evidence, an acceptance mapping, and a PR-body draft.
Merge remains a **manual human action** in Phase 1. Conveyor must not auto-merge
or auto-deploy in Phase 1.

Conveyor may record the human integration decision, merge commit, and follow-up
evidence, but that recording is not merge authority. The product claim for Phase
1 is local implementation with PR-quality evidence, not autonomous repository or
deployment control.

## Capability Gates

The autonomy ceiling for a run is the lowest level supported by the agent
adapter, sandbox, credential posture, project policy, and verification surface.
An adapter can run below its theoretical capability if any surrounding control
is weaker than the adapter itself.

| Capability | Required for L1 | Required for L2 | Required for L3 |
| ---------- | --------------- | --------------- | --------------- |
| Clean sandbox execution | Required | Required | Required |
| Independent gate rerun | Required | Required | Required |
| Diff captured from fresh base | Required | Required | Required |
| Structured final output | Warning if absent | Required | Required |
| Streaming events and heartbeat | Required | Required | Required |
| Cancellation | Best-effort allowed | Best-effort allowed | Hard or externally enforced |
| Pre-exec command policy | Observe-only allowed with hardened sandbox | Required | Required |
| Credential broker integration | Preferred | Required | Required |
| Cost and budget reporting | Estimated allowed | Required when provider supports it | Required |
| Reviewer actor separation | Required for gate | Required | Required |
| Canary health freshness | Required | Required | Required |

Phase-1 Pi profiles use this ceiling explicitly:

| Profile | Description | Autonomy ceiling |
| ------- | ----------- | ---------------- |
| `pi_host_controlled_tools` | Pi control loop runs outside the sandbox while tool calls are routed through Conveyor `ToolExecutor` inside the sandbox. | L1 with L2-shaped artifacts |
| `pi_in_container_observe_only` | The whole Pi process runs inside Docker; Conveyor observes the transcript and relies on stricter sandbox limits because it lacks pre-exec interception. | L1 only |

MCP tools and slash-command file handling do not bypass the dial. They must
still route through project policy, command normalization, `ToolInvocation`
recording, normalized agent events, and independent evidence capture.

## Gate Metrics For Promotion

Promotion to a higher autonomy level requires measured trust over real runs,
not a configuration flip. At minimum, the gate must track:

- Evidence completeness: every acceptance criterion is mapped to independent
  verification, artifacts, or an explicit blocker.
- Gate reproducibility: rerunning required checks from a fresh base produces the
  same pass/fail result.
- False-negative rate: reviewer or post-merge findings that should have blocked
  the Slice trend toward zero under the configured threshold.
- Reviewer outcomes: independent reviewers agree with the acceptance mapping,
  diff scope, and residual-risk summary.
- Policy incidents: blocked commands, credential access attempts, network
  violations, and sandbox escapes remain within the promotion threshold.
- Canary freshness: baseline health and gate-canary signals are current for the
  repository before higher authority is granted.
- Integration health: merged work does not increase rollback, revert, hotfix, or
  escaped-defect rates beyond the project threshold.
- Cost and cancellation behavior: runs stay inside budget and can be cancelled
  according to the level's requirement.

Promotion is reversible. A regression in gate quality, sandbox enforcement,
adapter behavior, credentials, reviewer independence, or project health lowers
the effective autonomy ceiling until new evidence restores trust.

## Phase Boundary

Phase 1 must stay at L1 even if a single run appears capable of more. L2-shaped
artifacts are produced so humans can review and merge efficiently, and so future
promotion has comparable evidence. They are not permission to create PRs, merge,
or deploy without a later policy decision and measured gate performance.
