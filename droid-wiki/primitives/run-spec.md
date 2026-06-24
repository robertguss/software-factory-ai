# Run spec

A run spec is the immutable execution capsule describing exactly what one
production slice attempt will run. It captures the full locked context for the
attempt: the contract lock digest, the base commit, the policy and diff policy
digests, the test pack digest, the lowered station plan, the container image
reference and digest, the sandbox profile, the budget digest, the code quality
profile, and the canary suite version. The run spec assembler builds it from
the slice's locked contract, work graph, and workspace context, and it is
content-addressed so the same inputs always produce the same spec.

## Key attributes

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `attempt_no` | `:integer` | Attempt sequence number this spec targets. Required. |
| `run_spec_json_ref` | `:string` | Reference to the canonical JSON artifact. Required. |
| `run_spec_sha256` | `:string` | Content-addressed digest of the spec. Required; unique. |
| `base_commit` | `:string` | Git commit the attempt starts from. Required. |
| `contract_lock_sha256` | `:string` | Digest of the locked contract. Required. |
| `prompt_template_version` | `:string` | Version of the prompt template. Required. |
| `agent_profile_snapshot` | `:map` | Snapshot of the agent profile at assembly time. Default `%{}`. |
| `policy_sha256` | `:string` | Digest of the policy profile. Required. |
| `diff_policy_sha256` | `:string` | Digest of the diff policy. Required. |
| `test_pack_sha256` | `:string` | Digest of the test pack. Required. |
| `station_plan` | `:map` | Lowered station plan (`conveyor.station_plan@1`). Required. |
| `station_plan_sha256` | `:string` | Digest of the station plan. Required. |
| `container_image_ref` | `:string` | Container image reference for the sandbox. Required. |
| `container_image_digest` | `:string` | Container image digest for reproducibility. Required. |
| `sandbox_profile` | `:string` | Sandbox isolation profile name. Required. |
| `budget_sha256` | `:string` | Digest of the run budget. Required. |
| `code_quality_profile` | `:string` | Code quality profile name. Required. |
| `canary_suite_version` | `:string` | Canary suite version for gate freshness. Required. |
| `created_at` | `:utc_datetime_usec` | Create timestamp. |

Run specs do not have a state machine. Only `create` and `read` actions are
exposed; the spec is immutable once assembled. A `StationPlan` validation
runs on create to assert the station plan is well-formed.

## Relationships

| Relationship | Type | Target |
| ------------ | ---- | ------ |
| `slice` | belongs_to (required) | `Conveyor.Factory.Slice` |
| `toolchain_profile` | belongs_to (optional) | `Conveyor.Factory.ToolchainProfile` |
| `run_attempts` | has_many | `Conveyor.Factory.RunAttempt` |
| `workspace_materializations` | has_many | `Conveyor.Factory.WorkspaceMaterialization` |
| `credential_leases` | has_many | `Conveyor.Factory.CredentialLease` |

## Identities

| Identity | Fields | Notes |
| -------- | ------ | ----- |
| `unique_run_spec_sha256` | `run_spec_sha256` | Spec digests are globally unique. |

## Key source files

| File | Role |
| ---- | ---- |
| `lib/conveyor/factory/run_spec.ex` | Ash resource definition. |
| `lib/conveyor/planning/run_spec_assembler.ex` | Builds the immutable RunSpec from a slice's locked contract and workspace context. |
| `lib/conveyor/factory/validations/station_plan.ex` | Validates the station plan on create. |
| `lib/conveyor/planning/work_graph_to_station_plan.ex` | Lowers a work graph slice to the station plan embedded in the spec. |

See also: [Slice](slice.md), [Run attempt](run-attempt.md),
[Contract lock](contract-lock.md), [Station run](station-run.md),
[Planning compiler](../systems/planning-compiler.md),
[Station pipeline](../features/station-pipeline.md).
