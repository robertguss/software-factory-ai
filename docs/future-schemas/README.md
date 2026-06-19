# Deferred Resource Schema Sketches

These notes reserve vocabulary for resources that later Conveyor phases are
expected to need. They are not Phase 1 public artifact schemas, Ash resources,
database tables, or migrations. Promotion requires a later bead to turn a sketch
into a concrete schema with examples, compatibility rules, and migration plan.

The sketches follow the current plan vocabulary:

- Source identity should use stable SourceAnchors, not path or line-number
  identity alone.
- Authority-bearing records must cite the grant, decision, evidence, policy, or
  artifact that authorized them.
- Events are expected to be append-only facts; current state can be projected
  from those events when possible.
- Any field with policy, budget, merge, memory, or trust impact needs an
  explicit provenance path before it can become runtime authority.

## WorkspacePool

### Purpose

Tracks isolated execution workspaces for later parallel fleet phases: checked
out worktrees, containers, runtime images, leases, and cleanup state. The goal is
to let the Dispatcher place attempts into bounded, fenced workspaces without
turning workspace lifecycle into ad hoc process state.

### Key Fields

- `workspace_pool_id`: Stable resource id.
- `project_ref`: Project or repository authority scope.
- `workspace_ref`: Opaque workspace/worktree/container identity.
- `image_ref`: Runtime image digest or build artifact digest.
- `base_commit`: Git commit used to create the workspace.
- `status`: `available`, `leased`, `quarantined`, `cleaning`, `retired`.
- `leased_to_run_ref`: Current StationRun/AgentRun ref, when leased.
- `lease_epoch`: Monotonic fencing counter.
- `lease_expires_at`: Time after which a watchdog may recover the workspace.
- `credential_scope_refs`: Credential leases allowed inside the workspace.
- `effect_receipt_refs`: Tool effects observed from this workspace.
- `last_health_check_at`: Last container/worktree health observation.

### Invariants

- A workspace can have at most one active lease per `lease_epoch`.
- Effects from a workspace must cite the matching `lease_epoch`.
- A workspace cannot return to `available` until cleanup has verified no
  uncommitted authorized outputs, live processes, or checked-out credentials.
- `base_commit` and `image_ref` are immutable for a leased workspace.
- Quarantined workspaces cannot be assigned to new attempts.

### Expected Event Types

- `conveyor.workspace_pool.registered`
- `conveyor.workspace_pool.health_checked`
- `conveyor.workspace_pool.leased`
- `conveyor.workspace_pool.lease_renewed`
- `conveyor.workspace_pool.released`
- `conveyor.workspace_pool.quarantined`
- `conveyor.workspace_pool.cleaned`
- `conveyor.workspace_pool.retired`

### Promotion Notes

Promote in the Phase 3 WorkerPool/parallel fleet work. Promotion must define the
boundary between persistent pool records and transient container supervisor
state, plus cleanup idempotency and effect-receipt reconciliation. Do not
promote before fenced station leases, cancellation checks, and credential
checkout semantics exist.

## TaskClaim

### Purpose

Represents an atomic claim on a ready unit of work by an actor or station
attempt. It is the durable counterpart to ready-pool dispatch and prevents two
workers from starting the same execution-hard work item.

### Key Fields

- `task_claim_id`: Stable claim id.
- `task_ref`: Slice, StationRun, ExternalTaskRef, or later work-graph node.
- `claimant_ref`: Actor, agent adapter, or dispatcher identity.
- `run_ref`: StationRun/AgentRun created by the claim.
- `claim_epoch`: Monotonic fencing counter for the task.
- `status`: `active`, `completed`, `expired`, `revoked`, `superseded`.
- `claimed_at`: Claim creation time.
- `expires_at`: Lease expiry time.
- `grant_refs`: QualificationGrant or policy grant refs checked at claim time.
- `budget_reservation_ref`: Budget reservation checked at claim time.
- `source_anchor_refs`: Stable anchors for task scope and authority inputs.

### Invariants

- A task can have only one active claim for the same execution-hard scope.
- `claim_epoch` must increase whenever a new claim supersedes an old claim.
- A claim cannot become `active` unless readiness, grants, budget, blockers, and
  emergency-stop state were checked in the same transaction boundary.
- Effects, evidence, and merge readiness from a run must cite the claim id and
  epoch that authorized the run.
- Expired or revoked claims cannot publish new authority-bearing artifacts.

### Expected Event Types

- `conveyor.task_claim.requested`
- `conveyor.task_claim.granted`
- `conveyor.task_claim.renewed`
- `conveyor.task_claim.completed`
- `conveyor.task_claim.expired`
- `conveyor.task_claim.revoked`
- `conveyor.task_claim.superseded`

### Promotion Notes

Promote with the Phase 3 Dispatcher or any earlier durable retry system that
needs claim fencing. Promotion must reuse existing station lease and
PermitCheckpoint semantics instead of inventing a second authorization path.
The first implementation should be narrow: claim a StationRun or Slice attempt,
not arbitrary future work graph nodes.

## MergeQueueItem

### Purpose

Serializes integration into `dev` after an isolated attempt passes its local
gate. It records merge intent, freshness checks, authority roots, conflicts,
and final integration outcome so fleet execution stays parallel while merge
authority stays serial.

### Key Fields

- `merge_queue_item_id`: Stable queue item id.
- `project_ref`: Repository/project scope.
- `source_branch_ref`: Candidate branch or patch artifact.
- `target_branch`: Usually `dev` until later promotion rules exist.
- `run_ref`: AgentRun or StationRun that produced the candidate.
- `task_claim_ref`: Claim that authorized the producing attempt.
- `approval_root_refs`: Approval roots checked at enqueue and merge time.
- `gate_result_ref`: Latest gate artifact used for enqueue or merge.
- `interface_contract_refs`: Contracts affected by the candidate.
- `conflict_domain_refs`: Files, symbols, interfaces, or work-graph domains that
  advisory checks believe may conflict.
- `status`: `queued`, `checking`, `blocked`, `merging`, `merged`, `failed`,
  `canceled`.
- `position`: Queue order within a target branch.
- `freshness_checked_at`: Last time gates and obligations were checked against
  the target.

### Invariants

- Only one item may be in `merging` for a target branch at a time.
- Enqueue and merge both require fresh gate results against the relevant target.
- Merge cannot proceed if approval roots, active grants, emergency-stop state,
  or required obligations fail recheck.
- Queue order can change only through an explicit event with reason and actor.
- A merged item must point to the resulting commit and immutable gate evidence.

### Expected Event Types

- `conveyor.merge_queue_item.enqueued`
- `conveyor.merge_queue_item.reordered`
- `conveyor.merge_queue_item.freshness_check_started`
- `conveyor.merge_queue_item.freshness_check_passed`
- `conveyor.merge_queue_item.freshness_check_failed`
- `conveyor.merge_queue_item.blocked`
- `conveyor.merge_queue_item.merge_started`
- `conveyor.merge_queue_item.merged`
- `conveyor.merge_queue_item.failed`
- `conveyor.merge_queue_item.canceled`

### Promotion Notes

Promote in Phase 3 after isolated workspace execution and gate artifacts are
durable. Promotion must first target `dev` only and must not imply auto-promotion
to `main`. Conflict domains are advisory until validated by deterministic gates
and cannot replace serial integration checks.

## BudgetLedger

### Purpose

Records budget reservations, spend, refunds, and circuit-breaker inputs for the
economic governor. Cost is a scheduling and kill-switch input, not just a
dashboard report.

### Key Fields

- `budget_ledger_id`: Stable ledger entry id.
- `scope_ref`: Global, project, plan, run, station, provider, or actor scope.
- `entry_kind`: `allocation`, `reservation`, `charge`, `refund`, `adjustment`,
  `release`.
- `amount`: Numeric amount in the ledger unit.
- `unit`: `usd`, `tokens`, `tool_calls`, `compute_seconds`, or a later explicit
  unit.
- `provider_ref`: Provider or tool adapter that generated the charge.
- `run_ref`: Related StationRun/AgentRun when applicable.
- `budget_reservation_ref`: Reservation consumed or released by the entry.
- `policy_decision_ref`: Policy decision that allowed or denied the spend.
- `idempotency_key`: Provider or conductor key used to prevent double charges.
- `occurred_at`: When the spend/reservation fact occurred.
- `source_anchor_refs`: Anchors for authority-bearing budget inputs.

### Invariants

- Charges must be idempotent by `idempotency_key` within a provider/scope.
- Spend cannot exceed active hard budget limits unless an explicit
  HumanDecision or emergency policy permits it.
- Reservations must be released, charged, expired, or revoked exactly once.
- Ledger entries are append-only; corrections are adjustment entries, not edits.
- Scheduler projections must be derivable from the ledger plus policy state.

### Expected Event Types

- `conveyor.budget_ledger.allocated`
- `conveyor.budget_ledger.reserved`
- `conveyor.budget_ledger.charged`
- `conveyor.budget_ledger.refunded`
- `conveyor.budget_ledger.released`
- `conveyor.budget_ledger.adjusted`
- `conveyor.budget_ledger.limit_exceeded`
- `conveyor.budget_ledger.circuit_opened`
- `conveyor.budget_ledger.circuit_closed`

### Promotion Notes

Promote in Phase 6, or earlier only for the minimal global/project budget checks
needed by Phase 3 dispatch. Promotion must align with emergency-stop and
reservation semantics from the budget ADRs so budget authority is checked before
claim, external effect, and publication.

## AgentReputation

### Purpose

Stores evidence-derived reliability signals for agent adapters, model profiles,
or specific qualified capability scopes. Reputation may inform routing and
review intensity, but it cannot grant authority by itself.

### Key Fields

- `agent_reputation_id`: Stable reputation record id.
- `subject_ref`: Agent adapter, model profile, tool profile, or qualified
  capability scope.
- `scope_ref`: Project, task class, interface kind, provider, or station kind.
- `window_start` and `window_end`: Measurement window.
- `sample_count`: Number of completed attempts in the window.
- `success_rate`: Gate-success ratio for the scoped window.
- `rework_rate`: Rate of needs-rework or human intervention.
- `budget_efficiency`: Cost or token efficiency compared with scoped baseline.
- `freshness_status`: `current`, `stale`, `insufficient_data`, `retired`.
- `evidence_refs`: Gate, review, run, and failure taxonomy artifacts.
- `confidence`: `high`, `medium`, `low`, `not_assessed`.
- `source_anchor_refs`: Stable anchors for evidence inputs.

### Invariants

- Reputation is derived from recorded evidence, never from hidden preference or
  unverifiable model self-report.
- Reputation cannot replace QualificationGrant, PolicyDecision, or human
  approval requirements.
- Scores must be scoped; a good result in one task class does not authorize a
  different class.
- Low-sample or stale windows must be labeled and cannot drive hard automation.
- Corrections to source evidence must invalidate or recompute affected scores.

### Expected Event Types

- `conveyor.agent_reputation.window_opened`
- `conveyor.agent_reputation.evidence_added`
- `conveyor.agent_reputation.score_computed`
- `conveyor.agent_reputation.score_invalidated`
- `conveyor.agent_reputation.window_closed`
- `conveyor.agent_reputation.retired`

### Promotion Notes

Promote after enough Phase 3-6 execution data exists to calibrate routing
without overfitting. The first promoted version should be read-only advisory
data for dispatcher ranking and review intensity. It must not become an
authorization primitive.

## Memory

### Purpose

Captures explicit, inspectable project and user memory: approved decisions,
project conventions, recurring risks, failure patterns, and user defaults.
Memory is meant to improve future context packs and run prompts while preserving
source evidence, scope, confidence, TTL, and delete controls.

### Key Fields

- `memory_id`: Stable memory id.
- `scope_ref`: User, project, repository, plan, interface, station, or task
  class scope.
- `memory_kind`: `decision`, `convention`, `risk`, `failure_pattern`,
  `preference`, `example`, `anti_pattern`.
- `statement`: Human-readable memory text.
- `status`: `candidate`, `active`, `contradicted`, `expired`, `deleted`,
  `retired`.
- `confidence`: `high`, `medium`, `low`, `not_assessed`.
- `source_anchor_refs`: Evidence, HumanDecision, review, or artifact anchors.
- `derived_from_memory_refs`: Source memories for summaries or consolidations.
- `ttl_expires_at`: Optional expiry time.
- `last_validated_at`: Last validation against current evidence.
- `delete_control_ref`: User/project delete or redaction authority.
- `embedding_ref`: Optional vector index pointer, not authoritative content.

### Invariants

- Hidden sticky memory is prohibited; all active memory must be inspectable.
- Derived summaries must cite source memories and evidence.
- Contradicting evidence invalidates or demotes affected memory before reuse.
- Deleted or redacted memory cannot be injected into future prompts.
- Embeddings are search accelerators only; authority lives in the memory record
  and its SourceAnchors.
- Scope must be explicit; project memory cannot silently become user-global
  memory.

### Expected Event Types

- `conveyor.memory.candidate_created`
- `conveyor.memory.approved`
- `conveyor.memory.activated`
- `conveyor.memory.used_in_context_pack`
- `conveyor.memory.contradicted`
- `conveyor.memory.expired`
- `conveyor.memory.deleted`
- `conveyor.memory.summary_derived`
- `conveyor.memory.invalidated`

### Promotion Notes

Promote in Phase 7 learning-loop work, or in the later explicit memory product
track. Promotion must include UI or report affordances for inspection, edit,
delete, TTL, scope, confidence, and provenance. The first implementation should
store explicit records before adding vector recall or prompt-template
optimization.

## ExternalTaskRef

### Purpose

Links Conveyor work to an external task tracker item, such as a Beads issue,
GitHub issue, ticket, or imported planning record. It lets Conveyor preserve
external identity and synchronization state without making an external tracker
the source of runtime authority.

### Key Fields

- `external_task_ref_id`: Stable Conveyor-side reference id.
- `system`: External system key, such as `br`, `github`, or `jira`.
- `external_id`: External task id in that system.
- `external_url`: Optional human-facing URL.
- `project_ref`: Conveyor project/repository scope.
- `local_task_ref`: Conveyor Plan, Epic, Slice, or work-graph node.
- `sync_status`: `linked`, `imported`, `export_pending`, `synced`,
  `conflict`, `unlinked`, `retired`.
- `last_seen_revision`: External revision, updated timestamp, or digest.
- `last_synced_at`: Last successful sync time.
- `field_map_ref`: Mapping profile used for imported/exported fields.
- `authority_mode`: `external_reference_only`, `external_source`,
  `conveyor_source`.
- `source_anchor_refs`: Anchors for imported text or decisions.

### Invariants

- A local task may have multiple external references, but at most one active ref
  per `system` and `external_id`.
- External text imported into authority-bearing Conveyor fields must receive
  stable SourceAnchors.
- Sync conflicts must not silently overwrite approved Conveyor semantics.
- `authority_mode` must be explicit before external updates can change local
  planning state.
- Retired or unlinked refs cannot receive new sync writes.

### Expected Event Types

- `conveyor.external_task_ref.linked`
- `conveyor.external_task_ref.imported`
- `conveyor.external_task_ref.sync_requested`
- `conveyor.external_task_ref.synced`
- `conveyor.external_task_ref.conflict_detected`
- `conveyor.external_task_ref.unlinked`
- `conveyor.external_task_ref.retired`

### Promotion Notes

Promote when Conveyor needs durable integration with Beads, GitHub, or another
task source beyond manual references. Early promotion should be read-mostly:
preserve external ids and imported SourceAnchors before attempting bidirectional
sync. Any mutating sync must respect the PlanRevision and HumanDecision model.
