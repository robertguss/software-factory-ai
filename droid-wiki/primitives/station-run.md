# Station run

A station run is the per-station execution record within a run attempt. It
tracks a single execution of a station (implementer, evidence recorder, context
scout, baseline health, acceptance calibration, verify) with lease and
idempotency metadata. Each station run carries a unique idempotency key, a
station spec digest, input and output digests, a lease owner and epoch for
fencing, heartbeat timestamps, and error details. The station execution
wrapper in `lib/conveyor/station.ex` owns the lease lifecycle and the declared
effects that support crash-safe reconciliation.

The station effect, effect attempt, and effect receipt resources form the
crash-safe side-effect reconciliation layer beneath each station run.

## Key attributes

### Station run

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `station` | `:string` | Station key (for example `implementer`, `verify`). Required. |
| `attempt_no` | `:integer` | Attempt number within the run attempt. Required. |
| `station_spec_sha256` | `:string` | Digest of the station spec. Required. |
| `idempotency_key` | `:string` | Unique idempotency key for the station run. Required; globally unique. |
| `input_sha256` | `:string` | Digest of the station input. Required. |
| `output_sha256` | `:string` | Digest of the station output. |
| `status` | `:atom` | One of `queued`, `running`, `succeeded`, `failed`, `cancelled`, `stale`. Default `queued`. |
| `lease_owner` | `:string` | Process or node that holds the lease. |
| `lease_owner_instance_id` | `:string` | Instance id of the lease owner. |
| `lease_epoch` | `:integer` | Lease fencing epoch. Default `0`. Required. |
| `lease_acquired_at` | `:utc_datetime_usec` | When the lease was acquired. |
| `lease_expires_at` | `:utc_datetime_usec` | When the lease expires. |
| `heartbeat_at` | `:utc_datetime_usec` | Last heartbeat timestamp. |
| `trace_id` | `:string` | Distributed trace id. |
| `started_at` | `:utc_datetime_usec` | When the station started running. |
| `completed_at` | `:utc_datetime_usec` | When the station reached a terminal state. |
| `error_category` | `:string` | Error classification on failure. |
| `error_message` | `:string` | Error detail on failure. |
| `artifact_refs` | `{:array, :string}` | References to artifacts produced by the station. Default `[]`. |

### Station effect

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `effect_kind` | `:atom` | One of `container_start`, `process_exec`, `file_write`, `provider_call`, `artifact_project`. Required. |
| `idempotency_key` | `:string` | Unique idempotency key. Required; globally unique. |
| `declared_at` | `:utc_datetime_usec` | Create timestamp. |
| `started_at` | `:utc_datetime_usec` | When the effect started. |
| `completed_at` | `:utc_datetime_usec` | When the effect completed. |
| `observed_ref` | `:string` | Reference to the observed side effect. |
| `status` | `:atom` | One of `declared`, `running`, `succeeded`, `failed`, `unknown`, `reconciled`. Default `declared`. |
| `cleanup_required` | `:boolean` | Whether cleanup is needed. Default `false`. |
| `cleanup_status` | `:atom` | One of `not_required`, `pending`, `completed`, `failed`. Default `not_required`. |

### Effect attempt

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `fencing_token` | `:string` | Fencing token for the attempt. Required. |
| `admission_permit_id` | `:string` | Admission permit id. Required. |
| `idempotency_key` | `:string` | Unique idempotency key. Required; globally unique. |
| `request_digest` | `:string` | Digest of the request. Required. |
| `started_at` | `:utc_datetime_usec` | When the attempt started. Required. |
| `completed_at` | `:utc_datetime_usec` | When the attempt completed. |
| `status` | `:atom` | One of `started`, `externally_accepted`, `failed`, `outcome_unknown`. Default `started`. |

Effect attempts are separate from receipts so `outcome_unknown` is represented
explicitly rather than collapsed into success or failure.

### Effect receipt

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `fencing_token` | `:string` | Fencing token matching the attempt. Required. |
| `idempotency_key` | `:string` | Unique idempotency key. Required; globally unique. |
| `external_correlation_id` | `:string` | Correlation id from the external system. |
| `request_digest` | `:string` | Digest of the request. Required. |
| `result_digest` | `:string` | Digest of the observed result. Required. |
| `reconciliation_status` | `:atom` | One of `pending`, `confirmed`, `absent`, `ambiguous`, `compensated`. Default `pending`. |
| `trace_id` | `:string` | Distributed trace id. Required. |
| `observed_at` | `:utc_datetime_usec` | When the receipt was observed. Required. |

## Relationships

| Resource | Relationship | Type | Target |
| -------- | ------------ | ---- | ------ |
| Station run | `run_attempt` | belongs_to (required) | `Conveyor.Factory.RunAttempt` |
| Station run | `agent_session` | belongs_to (optional) | `Conveyor.Factory.AgentSession` |
| Station run | `slice` | belongs_to (required) | `Conveyor.Factory.Slice` |
| Station run | `effects` | has_many | `Conveyor.Factory.StationEffect` |
| Station run | `workspace_materializations` | has_many | `Conveyor.Factory.WorkspaceMaterialization` |
| Station run | `tool_invocations` | has_many | `Conveyor.Factory.ToolInvocation` |
| Station run | `artifacts` | has_many | `Conveyor.Factory.Artifact` |
| Station run | `credential_leases` | has_many | `Conveyor.Factory.CredentialLease` |
| Station run | `ledger_events` | has_many | `Conveyor.Factory.LedgerEvent` |
| Station effect | `station_run` | belongs_to (required) | `Conveyor.Factory.StationRun` |
| Effect attempt | `station_run` | belongs_to (required) | `Conveyor.Factory.StationRun` |
| Effect attempt | `station_effect` | belongs_to (required) | `Conveyor.Factory.StationEffect` |
| Effect attempt | `receipts` | has_many | `Conveyor.Factory.EffectReceipt` |
| Effect receipt | `effect_attempt` | belongs_to (required) | `Conveyor.Factory.EffectAttempt` |

## Identities

| Resource | Identity | Fields |
| -------- | -------- | ------ |
| Station run | `unique_idempotency_key` | `idempotency_key` |
| Station effect | `unique_idempotency_key` | `idempotency_key` |
| Effect attempt | `unique_idempotency_key` | `idempotency_key` |
| Effect receipt | `unique_idempotency_key` | `idempotency_key` |

## Key source files

| File | Role |
| ---- | ---- |
| `lib/conveyor/factory/station_run.ex` | Station run Ash resource. |
| `lib/conveyor/factory/station_effect.ex` | Station effect Ash resource. |
| `lib/conveyor/factory/effect_attempt.ex` | Effect attempt Ash resource. |
| `lib/conveyor/factory/effect_receipt.ex` | Effect receipt Ash resource. |
| `lib/conveyor/station.ex` | Station behaviour wrapper; owns leases, idempotency, declared effects, and ledger events. |
| `lib/conveyor/planning/work_graph_to_station_plan.ex` | Lowers a work graph slice to the station plan. |

See also: [Run attempt](run-attempt.md), [Run spec](run-spec.md),
[Evidence](evidence.md), [Station pipeline](../features/station-pipeline.md),
[Gate](../systems/gate.md).
