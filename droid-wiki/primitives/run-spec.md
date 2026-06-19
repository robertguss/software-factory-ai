# Run spec

A run spec is the immutable, content-addressed input capsule that freezes exactly what one execution attempt will run against. It is the single object that makes Conveyor's evidence reproducible: if any input that affects evidence validity changes (contract, policy, AGENTS.md, test pack, toolchain, budgets), the run spec's SHA-256 changes, and prior evidence is no longer valid against the new inputs.

The resource lives in `lib/conveyor/factory/run_spec.ex` and is persisted in the `run_specs` Postgres table. It has only `read`, `destroy`, and `create` actions, and its `run_spec_sha256` is unique via the `unique_run_spec_sha256` identity. A `StationPlan` validation runs on create to ensure the embedded station plan is well-formed.

## Fields

| Field | Type | Notes |
| ---- | ---- | ---- |
| `id` | UUID | Primary key. |
| `attempt_no` | integer | Required. The attempt number this spec is for. |
| `run_spec_json_ref` | string | Required. Content-addressed reference to the full serialized run spec JSON. |
| `run_spec_sha256` | string | Required. SHA-256 of the canonical run spec; unique. |
| `base_commit` | string | Required. The git commit the attempt starts from. |
| `contract_lock_sha256` | string | Required. Digest of the [contract lock](contract-lock.md) in effect. |
| `prompt_template_version` | string | Required. Version of the prompt template used to assemble the implementation prompt. |
| `agent_profile_snapshot` | map | Required, default `%{}`. Snapshot of the agent profile (model, parameters) for reproducibility. |
| `policy_sha256` | string | Required. Digest of the policy profile in effect. |
| `diff_policy_sha256` | string | Required. Digest of the diff policy applied to the attempt. |
| `test_pack_sha256` | string | Required. Digest of the locked test pack mounted into the sandbox. |
| `station_plan` | map | Required. The ordered station plan the attempt will execute. |
| `station_plan_sha256` | string | Required. Digest of the station plan, so reordering or changing stations invalidates the spec. |
| `container_image_ref` | string | Required. Reference to the sandbox container image. |
| `container_image_digest` | string | Required. Digest of the container image, pinning the exact image. |
| `sandbox_profile` | string | Required. The sandbox profile (permissions, network restrictions) in effect. |
| `budget_sha256` | string | Required. Digest of the budgets (time, tokens, cost) for the attempt. |
| `code_quality_profile` | string | Required. The code quality profile used to evaluate the diff. |
| `canary_suite_version` | string | Required. Version of the canary suite used to verify the gate catches regressions. |
| `created_at` | utc_datetime_usec | Create timestamp. |
| `slice_id` | UUID | Required. The slice being attempted. |
| `toolchain_profile_id` | UUID | Optional. The toolchain profile pinning container image, SBOM, and tool versions. |

## Frozen inputs

The run spec freezes every input that could affect whether evidence is still valid. Grouped by concern:

- **Contract and policy** — `contract_lock_sha256`, `policy_sha256`, `diff_policy_sha256`, and `test_pack_sha256` pin the acceptance target, the permissions, the diff rules, and the tests. Any change here means a new run spec is required.
- **Instructions and prompts** — `prompt_template_version` and `agent_profile_snapshot` freeze how the agent is prompted and configured, so a prompt change does not silently invalidate evidence.
- **Station plan** — `station_plan` and `station_plan_sha256` pin the ordered sequence of stations. Reordering stations or adding a new one changes the digest.
- **Toolchain and sandbox** — `container_image_ref`, `container_image_digest`, `sandbox_profile`, and `toolchain_profile_id` pin the execution environment. The container image is pinned by digest, not just tag, so a re-pushed image with the same tag is detected.
- **Budgets and quality** — `budget_sha256`, `code_quality_profile`, and `canary_suite_version` pin the resource limits, the quality bar, and the canary suite used to test the gate itself.

## How run specs relate to attempts and retries

A [run attempt](run-attempt.md) belongs to exactly one run spec. When an attempt fails, `Conveyor.RunAttemptLifecycle.create_retry_attempt!/3` requires a fresh run spec: it checks that the new run spec's id differs from the failed attempt's, that it belongs to the same slice, and that its `attempt_no` is exactly one greater. This guarantees a retry always replans against current inputs rather than reusing a stale capsule.

## Relationships

| Relationship | Resource | Cardinality | Notes |
| ---- | ---- | ---- |
| `slice` | `Conveyor.Factory.Slice` | belongs_to (required) | The slice being attempted. |
| `toolchain_profile` | `Conveyor.Factory.ToolchainProfile` | belongs_to (optional) | Pinned container image, SBOM, and tool versions. |
| `run_attempts` | `Conveyor.Factory.RunAttempt` | has_many | Attempts that consume this spec. |
| `workspace_materializations` | `Conveyor.Factory.WorkspaceMaterialization` | has_many | Workspace materializations created from this spec. |
| `credential_leases` | `Conveyor.Factory.CredentialLease` | has_many | Short-lived credential leases issued for this spec. |

## Key source files

| File | Purpose |
| ---- | ---- |
| `lib/conveyor/factory/run_spec.ex` | Ash resource: frozen inputs, station plan, digests, relationships. |
| `lib/conveyor/factory/validations/station_plan.ex` | Validates the embedded station plan on create. |
| `lib/conveyor/run_attempt_lifecycle.ex` | Enforces fresh run spec on retry. |
| `lib/conveyor/factory/contract_lock.ex` | Source of the `contract_lock_sha256`. |
| `lib/conveyor/factory/toolchain_profile.ex` | Optional toolchain profile referenced by the spec. |

## Related pages

- [Primitives](index.md) — all foundational domain objects
- [Run attempt](run-attempt.md) — consumes a run spec
- [Contract lock](contract-lock.md) — the acceptance contract frozen by the spec
- [Slice](slice.md) — the work unit the spec is built for
- [Station run](station-run.md) — executes the station plan frozen by the spec
- [Architecture](../overview/architecture.md) — where the run spec sits in the pipeline
