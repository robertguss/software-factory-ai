# Contract lock

A contract lock is an immutable, machine-checkable acceptance contract that
freezes a slice's contract before execution. It stores a set of SHA-256 digests
over the plan contract, agent brief, acceptance criteria, required tests, test
pack, verification commands, AGENTS.md content, and policy, plus the
protected-path globs and the actor that locked it. Once locked, the contract
cannot change for the lifetime of the slice's attempts. The gate's contract
lock stage verifies that the run still matches the approved lock before
allowing a merge.

## Key attributes

| Attribute | Type | Description |
| --------- | ---- | ----------- |
| `id` | `:uuid` | Primary key. |
| `plan_contract_sha256` | `:string` | Digest of the normalized plan contract. Required. |
| `brief_sha256` | `:string` | Digest of the agent brief. Required. |
| `acceptance_criteria_sha256` | `:string` | Digest of the acceptance criteria. Required. |
| `required_tests_sha256` | `:string` | Digest of the required tests. Required. |
| `test_pack_sha256` | `:string` | Digest of the test pack. Required. |
| `verification_commands_sha256` | `:string` | Digest of the verification commands. Required. |
| `agents_md_sha256` | `:string` | Digest of the AGENTS.md content. Required. |
| `policy_sha256` | `:string` | Digest of the policy profile. Required. |
| `protected_path_globs` | `{:array, :string}` | Glob patterns for paths the agent must not touch. Default `[]`. |
| `locked_at` | `:utc_datetime_usec` | When the lock was created. Required. |
| `locked_by` | `:string` | Actor that created the lock. Required. |

Contract locks do not have a state machine. They are created once (only
`create` and `read` actions are exposed; no `update`) and are immutable for the
lifetime of the slice's attempts.

## Relationships

| Relationship | Type | Target |
| ------------ | ---- | ------ |
| `slice` | belongs_to (required) | `Conveyor.Factory.Slice` |
| `agent_brief` | belongs_to (required) | `Conveyor.Factory.AgentBrief` |

## Key source files

| File | Role |
| ---- | ---- |
| `lib/conveyor/factory/contract_lock.ex` | Ash resource definition. |
| `lib/conveyor/planning/run_spec_assembler.ex` | Materializes and locks the contract for a slice attempt. |
| `lib/conveyor/gate/stages/contract_lock.ex` | Gate stage that verifies the run matches the approved lock. |

See also: [Slice](slice.md), [Run spec](run-spec.md), [Evidence](evidence.md),
[Gate](../systems/gate.md), [Planning compiler](../systems/planning-compiler.md).
