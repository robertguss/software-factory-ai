# Data models

Conveyor's domain model is built with Ash 3.x and AshPostgres. The `Conveyor.Factory` domain in `lib/conveyor/factory.ex` registers 45 Ash resources covering projects, plans, slices, run attempts, evidence, reviews, gate results, policy, credentials, and more. State machines are modeled with `ash_state_machine`. Migrations are append-only in `priv/repo/migrations/`, and the repo module is `lib/conveyor/repo.ex`.

This page lists every resource registered in the domain, grouped by area, with its file path and a one-line description taken from the resource's `@moduledoc`. Keep resources and migrations aligned: an Ash resource change usually implies a migration and a focused test.

## Resource registry

The domain is declared in `lib/conveyor/factory.ex`:

```elixir
defmodule Conveyor.Factory do
  use Ash.Domain, otp_app: :conveyor

  resources do
    resource Conveyor.Factory.Project
    # ... 44 more
  end
end
```

### Project and toolchain

| Resource | File | Description |
| -------- | ---- | ----------- |
| `Project` | `lib/conveyor/factory/project.ex` | A repository registered with Conveyor. |
| `ToolchainProfile` | `lib/conveyor/factory/toolchain_profile.ex` | Pinned toolchain image and dependency identity for reproducible station runs. |
| `CacheMount` | `lib/conveyor/factory/cache_mount.ex` | Content-addressed cache mount observed during a station run. |

### Plan and work graph

| Resource | File | Description |
| -------- | ---- | ----------- |
| `Plan` | `lib/conveyor/factory/plan.ex` | A normalized implementation plan imported for deterministic readiness checks. |
| `Requirement` | `lib/conveyor/factory/requirement.ex` | A stable-key requirement traced from the normalized plan contract. |
| `HumanDecision` | `lib/conveyor/factory/human_decision.ex` | An explicit human decision captured during plan normalization. |
| `PlanAudit` | `lib/conveyor/factory/plan_audit.ex` | Deterministic readiness verdict and findings for an imported plan. |
| `Epic` | `lib/conveyor/factory/epic.ex` | A plan-level work grouping that owns ordered slices. |
| `Slice` | `lib/conveyor/factory/slice.ex` | An ordered implementation slice with readiness data for later scheduling. |

### Contracts and tests

| Resource | File | Description |
| -------- | ---- | ----------- |
| `AgentBrief` | `lib/conveyor/factory/agent_brief.ex` | Locked implementation contract for a slice. |
| `ContractLock` | `lib/conveyor/factory/contract_lock.ex` | Immutable digest set that freezes a slice contract for future evidence. |
| `TestPack` | `lib/conveyor/factory/test_pack.ex` | Locked read-only acceptance test bundle for a slice. |
| `VerificationSuite` | `lib/conveyor/factory/verification_suite.ex` | Classified command suite used for baseline, acceptance, quality, and gate checks. |
| `TestPackCalibration` | `lib/conveyor/factory/test_pack_calibration.ex` | Baseline red/green calibration result for a locked test pack. |

### Run execution

| Resource | File | Description |
| -------- | ---- | ----------- |
| `RunSpec` | `lib/conveyor/factory/run_spec.ex` | Immutable execution capsule describing exactly what one attempt will run. |
| `RunAttempt` | `lib/conveyor/factory/run_attempt.ex` | Parent identity for one execution attempt of a slice. |
| `AgentSession` | `lib/conveyor/factory/agent_session.ex` | Untrusted adapter session output for an implementer, reviewer, or scout. |
| `StationRun` | `lib/conveyor/factory/station_run.ex` | Per-station execution progress with lease and idempotency metadata. |
| `StationEffect` | `lib/conveyor/factory/station_effect.ex` | Declared external side effect for crash-safe station reconciliation. |
| `EffectAttempt` | `lib/conveyor/factory/effect_attempt.ex` | Recorded attempt to perform an external effect. |
| `EffectReceipt` | `lib/conveyor/factory/effect_receipt.ex` | Durable receipt and reconciliation state for an external effect attempt. |
| `WorkspaceMaterialization` | `lib/conveyor/factory/workspace_materialization.ex` | Tracked checkout/workspace lifecycle for stations and gate phases. |
| `RunBudget` | `lib/conveyor/factory/run_budget.ex` | Per-run resource caps and consumed counters for runaway protection. |

### Evidence and artifacts

| Resource | File | Description |
| -------- | ---- | ----------- |
| `Evidence` | `lib/conveyor/factory/evidence.ex` | Aggregated machine evidence for a run attempt and patch. |
| `PatchSet` | `lib/conveyor/factory/patch_set.ex` | Captured git diff and scope metrics for an agent-produced patch. |
| `PatchEquivalence` | `lib/conveyor/factory/patch_equivalence.ex` | Detailed comparison between accepted and externally applied patches. |
| `ExternalChange` | `lib/conveyor/factory/external_change.ex` | Human-applied external commit and patch equivalence classification. |
| `Artifact` | `lib/conveyor/factory/artifact.ex` | Content-addressed artifact metadata and projection identity. |
| `RunBundle` | `lib/conveyor/factory/run_bundle.ex` | Canonical run-directory manifest and bundle root digest. |
| `ToolInvocation` | `lib/conveyor/factory/tool_invocation.ex` | Recorded command/tool execution with policy and output references. |
| `CodeQualityRun` | `lib/conveyor/factory/code_quality_run.ex` | Code-quality adapter result and high-risk finding delta for scout and gate use. |
| `ContextPack` | `lib/conveyor/factory/context_pack.ex` | Cited scout output used to assemble bounded implementation prompts. |
| `InstructionSource` | `lib/conveyor/factory/instruction_source.ex` | Trust-labeled prompt input used to preserve instruction hierarchy boundaries. |
| `RunPrompt` | `lib/conveyor/factory/run_prompt.ex` | Versioned immutable prompt assembled from a brief, context pack, and policies. |
| `RiskAssessment` | `lib/conveyor/factory/risk_assessment.ex` | Planned-versus-observed risk comparison for a patch. |

### Review and gate

| Resource | File | Description |
| -------- | ---- | ----------- |
| `Review` | `lib/conveyor/factory/review.ex` | Reviewer verdict over a dossier. |
| `ReviewPolicy` | `lib/conveyor/factory/review_policy.ex` | Maps observed risk rules to required review kinds and escalation behavior. |
| `ReviewerHealth` | `lib/conveyor/factory/reviewer_health.ex` | Queryable reviewer fixture-suite health summary. |
| `GateResult` | `lib/conveyor/factory/gate_result.ex` | Deterministic gate verdict and freshness keys for a run attempt. |
| `GateHealth` | `lib/conveyor/factory/gate_health.ex` | Queryable gate freshness and honesty summary for a freshness key. |
| `DiffPolicy` | `lib/conveyor/factory/diff_policy.ex` | Bounds the allowed diff scope for a slice. |

### Policy, security, and authority

| Resource | File | Description |
| -------- | ---- | ----------- |
| `Policy` | `lib/conveyor/factory/policy.ex` | Named policy profile with command, environment, network, budget, and autonomy limits. |
| `RetentionPolicy` | `lib/conveyor/factory/retention_policy.ex` | Retention and deletion policy for artifact sensitivity classes. |
| `Incident` | `lib/conveyor/factory/incident.ex` | Policy, safety, and operational incident record. |
| `CredentialLease` | `lib/conveyor/factory/credential_lease.ex` | Short-lived scoped provider credential exposure record. |
| `HumanApproval` | `lib/conveyor/factory/human_approval.ex` | Human approval or recorded external action tied to a project run. |
| `AuthorityEvent` | `lib/conveyor/factory/authority_event.ex` | Canonical causal authority event for audit, recovery, and replay. |

### Ledger and events

| Resource | File | Description |
| -------- | ---- | ----------- |
| `LedgerEvent` | `lib/conveyor/factory/ledger_event.ex` | Append-only event timeline entry with a domain idempotency key. |
| `EventOutbox` | `lib/conveyor/factory/event_outbox.ex` | Transactional publication queue for committed ledger events. |

## Migrations

Migrations live in `priv/repo/migrations/` and are append-only. Each Ash resource maps to a Postgres table (for example, `Project` -> `projects`, `Slice` -> `slices`, `RunAttempt` -> `run_attempts`). The repo module is `lib/conveyor/repo.ex`. Keep resource changes and migrations aligned; a resource change usually implies a migration and a focused test in `test/conveyor/factory/`.

The factory resource tests are grouped by domain area in `test/conveyor/factory/`:

- `foundation_resources_test.exs`
- `execution_run_resources_test.exs`
- `work_graph_policy_resources_test.exs`
- `contract_spine_resources_test.exs`
- `evidence_verdict_resources_test.exs`
- `prompt_context_resources_test.exs`
- `artifact_health_resources_test.exs`
- `plan_quality_resources_test.exs`
- `patch_risk_workspace_resources_test.exs`
- `safety_audit_resources_test.exs`
- `db_invariants_test.exs`
- `embedded_schema_validation_test.exs`
- `run_spec_test.exs`

## State machines

Several resources use `ash_state_machine` with explicit states and transitions. For example, `Slice` transitions through `approved` -> `ready` -> `in_progress` -> `gated` -> `integrated` -> `complete` (and `policy_blocked` / `failed` on policy violation), and `RunAttempt` transitions through `running` -> `evidence_recorded` -> `reviewed` -> `gated` -> `reported` (and `failed`). States and database constraints are kept aligned.

See [Configuration](configuration.md) for how project config feeds into these resources, [Dependencies](dependencies.md) for the Ash stack that backs them, and [Architecture](../overview/architecture.md) for how the resources fit into the station pipeline.
