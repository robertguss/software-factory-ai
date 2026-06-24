# Evidence

Evidence is the aggregated machine evidence for a run attempt and its patch.
The evidence resource records what the agent did and what the verification
tools observed: changed files, the diff reference, tool invocation references,
acceptance results, code quality results, risks, a summary, and the PR body
reference. The gate's acceptance mapping stage consumes this evidence to verify
that every acceptance criterion has passing evidence before a slice can merge.

## Key attributes

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `changed_files` | `{:array, :string}` | Files changed by the attempt. Required; default `[]`. |
| `diff_ref` | `:string` | Reference to the diff artifact. Required. |
| `tool_invocation_refs` | `{:array, :string}` | References to recorded tool invocations. Default `[]`. |
| `acceptance_results` | `{:array, :map}` | Per-criterion acceptance check results. Default `[]`. |
| `code_quality_result_ref` | `:string` | Reference to the code quality run result. |
| `risks` | `{:array, :map}` | Observed risk assessments. Default `[]`. |
| `summary` | `:string` | Human-readable evidence summary. Required. |
| `pr_body_ref` | `:string` | Reference to the generated PR body artifact. |

Evidence does not have a state machine. It is an append-only record created
during the evidence recording station and read by the gate at finalization.

## Relationships

| Relationship | Type | Target |
| ------------ | ---- | ------ |
| `run_attempt` | belongs_to (required) | `Conveyor.Factory.RunAttempt` |
| `patch_set` | belongs_to (required) | `Conveyor.Factory.PatchSet` |

## Key source files

| File | Role |
| ---- | ---- |
| `lib/conveyor/factory/evidence.ex` | Ash resource definition. |
| `lib/conveyor/gate/stages/acceptance_mapping.ex` | Gate stage that verifies every acceptance criterion has passing evidence. |
| `lib/conveyor/evidence/` | Evidence capture, artifact, and comparison modules. |

See also: [Run attempt](run-attempt.md), [Slice](slice.md),
[Contract lock](contract-lock.md), [Gate](../systems/gate.md),
[Station pipeline](../features/station-pipeline.md).
