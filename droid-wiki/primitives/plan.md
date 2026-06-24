# Plan

The plan hierarchy is the top-level container for a project's work. A project
owns plans, a plan owns requirements and epics, and an epic owns ordered
slices. Plans enter the system either as a `conveyor.plan@1` YAML/JSON contract
(imported by the plan importer) or as DB-native task graph rows authored through
the task graph CLI. The normalized contract map is persisted on the plan and
carries a content-addressed digest so structural audits and the run path can
verify integrity.

## Key attributes

### Plan

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `title` | `:string` | Plan title. Required. |
| `intent` | `:string` | High-level intent statement. Required. |
| `source_document` | `:string` | Path or reference to the source plan document. Required. |
| `normalized_contract` | `:map` | The `conveyor.plan@1` contract map. Required. |
| `schema_version` | `:string` | Contract schema version, default `conveyor.plan@1`. |
| `contract_sha256` | `:string` | Digest of the normalized contract. Required. |
| `status` | `:atom` | Plan status. One of `draft`, `audited`, `handoff_ready`, `active`, `completed`, `needs_clarification`, `archived`. Default `draft`. |
| `readiness_score` | `:integer` | Computed readiness score. |
| `imported_at` | `:utc_datetime_usec` | Import timestamp. |

Plan status transitions are validated by
`Conveyor.Factory.Validations.PlanStatusTransition` on update.

### Epic

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `title` | `:string` | Epic title. Required. |
| `description` | `:string` | Epic description. Required. |
| `risk` | `:string` | Risk tier, default `medium`. Required. |
| `approval_status` | `:atom` | One of `not_required`, `pending`, `approved`, `rejected`. Default `not_required`. |
| `status` | `:atom` | One of `open`, `ready`, `in_progress`, `closed`, `deferred`. Default `open`. |

### Requirement

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `stable_key` | `:string` | Stable requirement key. Required; unique per plan. |
| `text` | `:string` | Requirement text. Required. |
| `section_ref` | `:string` | Reference to the source section. Required. |
| `source_span` | `:map` | Source span in the plan document. Default `%{}`. |
| `contract_sha256` | `:string` | Digest of the contract the requirement was traced from. Required. |
| `status` | `:atom` | One of `covered`, `deferred`, `out_of_scope`, `open`. Default `open`. |
| `risk` | `:string` | Risk tier, default `low`. Required. |
| `notes` | `:string` | Optional notes. |

### Project

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `name` | `:string` | Project name. Required. |
| `repo_url` | `:string` | Repository URL. |
| `local_path` | `:string` | Local filesystem path. Required. |
| `default_branch` | `:string` | Default git branch, default `main`. Required. |
| `dev_branch` | `:string` | Development branch. |
| `command_specs` | `{:array, :map}` | Command specifications for the project. Default `[]`. Validated against the `command_specs` embedded schema. |
| `toolchain_profile_id` | `:uuid` | Default toolchain profile. |
| `code_quality_profile` | `:string` | Code quality profile, default `standard`. Required. |
| `default_autonomy_level` | `:integer` | Default autonomy level, default `1`. Required. |
| `status` | `:atom` | One of `active`, `archived`. Default `active`. |

## Relationships

| Resource | Relationship | Type | Target |
| -------- | ------------ | ---- | ------ |
| Project | `toolchain_profiles` | has_many | `Conveyor.Factory.ToolchainProfile` |
| Project | `plans` | has_many | `Conveyor.Factory.Plan` |
| Project | `review_policies` | has_many | `Conveyor.Factory.ReviewPolicy` |
| Project | `verification_suites` | has_many | `Conveyor.Factory.VerificationSuite` |
| Project | `gate_health_checks` | has_many | `Conveyor.Factory.GateHealth` |
| Project | `code_quality_runs` | has_many | `Conveyor.Factory.CodeQualityRun` |
| Project | `retention_policies` | has_many | `Conveyor.Factory.RetentionPolicy` |
| Project | `incidents` | has_many | `Conveyor.Factory.Incident` |
| Project | `human_approvals` | has_many | `Conveyor.Factory.HumanApproval` |
| Project | `ledger_events` | has_many | `Conveyor.Factory.LedgerEvent` |
| Plan | `project` | belongs_to (required) | `Conveyor.Factory.Project` |
| Plan | `requirements` | has_many | `Conveyor.Factory.Requirement` |
| Plan | `human_decisions` | has_many | `Conveyor.Factory.HumanDecision` |
| Plan | `audits` | has_many | `Conveyor.Factory.PlanAudit` |
| Plan | `epics` | has_many | `Conveyor.Factory.Epic` |
| Epic | `plan` | belongs_to (required) | `Conveyor.Factory.Plan` |
| Epic | `slices` | has_many | `Conveyor.Factory.Slice` |
| Requirement | `plan` | belongs_to (required) | `Conveyor.Factory.Plan` |

## Identities

| Resource | Identity | Fields |
| -------- | -------- | ------ |
| Requirement | `unique_plan_stable_key` | `plan_id`, `stable_key` |

## Key source files

| File | Role |
| ---- | ---- |
| `lib/conveyor/factory/project.ex` | Project Ash resource. |
| `lib/conveyor/factory/plan.ex` | Plan Ash resource with status transition validation. |
| `lib/conveyor/factory/epic.ex` | Epic Ash resource. |
| `lib/conveyor/factory/requirement.ex` | Requirement Ash resource. |
| `lib/conveyor/planning/plan_importer.ex` | One-time YAML to DB rows migration. |
| `lib/conveyor/planning/contract_builder.ex` | Compiles DB rows to the `normalized_contract` map. |
| `lib/conveyor/planning/plan_runner.ex` | Runs a persisted plan through the serial driver. |
| `lib/conveyor/task_graph.ex` | DB-native task graph authoring and querying. |
| `lib/conveyor/plan_contract.ex` | Loads and validates `conveyor.plan@1` contracts. |

See also: [Slice](slice.md), [Contract lock](contract-lock.md),
[Run spec](run-spec.md), [Planning compiler](../systems/planning-compiler.md),
[Contract management](../features/contract-management.md).
