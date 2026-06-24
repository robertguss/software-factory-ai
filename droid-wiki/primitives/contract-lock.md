# Contract lock

A contract lock is an immutable, machine-checkable acceptance contract that
freezes a slice's public interface, required tests, and definition of done
before any evidence is recorded. It is the target that later evidence is checked
against, and because it is authored by a different actor than the implementer,
it is the structural enforcement of Conveyor's separation of concerns: the agent
that writes the contract cannot be the agent that implements against it.

The resource lives in `lib/conveyor/factory/contract_lock.ex` and is persisted
in the `contract_locks` Postgres table. It has no state machine and only `read`,
`destroy`, and `create` actions: once written, a contract lock is not updated.
Evolution happens by creating a new contract lock, not by mutating the old one.

## Fields

Every field that affects acceptance is frozen as a SHA-256 digest. This means
the gate can verify that the inputs it evaluates against match the inputs that
were locked, without trusting any mutable state.

| Field                          | Type              | Notes                                                                                                                          |
| ------------------------------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `id`                           | UUID              | Primary key.                                                                                                                   |
| `plan_contract_sha256`         | string            | Required. Digest of the normalized plan contract (`conveyor.plan@1`).                                                          |
| `brief_sha256`                 | string            | Required. Digest of the agent brief handed to the implementer.                                                                 |
| `acceptance_criteria_sha256`   | string            | Required. Digest of the acceptance criteria the slice must meet.                                                               |
| `required_tests_sha256`        | string            | Required. Digest of the required test set.                                                                                     |
| `test_pack_sha256`             | string            | Required. Digest of the locked test pack mounted into the sandbox.                                                             |
| `verification_commands_sha256` | string            | Required. Digest of the verification commands run against the slice.                                                           |
| `agents_md_sha256`             | string            | Required. Digest of the project AGENTS.md in effect, so instruction drift invalidates prior evidence.                          |
| `policy_sha256`                | string            | Required. Digest of the policy profile in effect when the lock was created.                                                    |
| `protected_path_globs`         | array of strings  | Required, default `[]`. Glob patterns for paths the implementation must not touch.                                             |
| `locked_at`                    | utc_datetime_usec | Required. When the lock was created.                                                                                           |
| `locked_by`                    | string            | Required. The actor that created the lock. The slice lifecycle enforces that the implementation actor differs from this value. |
| `slice_id`                     | UUID              | Required. The slice the lock belongs to.                                                                                       |
| `agent_brief_id`               | UUID              | Required. The agent brief the lock freezes.                                                                                    |

## Interface freeze, test requirements, and definition of done

The contract lock bundles three concerns into one immutable record:

- **Interface freeze** — `acceptance_criteria_sha256` and `protected_path_globs`
  pin the public interface and the paths that are off-limits. If the
  implementation touches a protected path or changes the interface, the gate
  sees it.
- **Test requirements** — `required_tests_sha256`, `test_pack_sha256`, and
  `verification_commands_sha256` freeze the tests and commands that will be run.
  The test pack is read-only during implementation, so the implementer cannot
  weaken the tests to pass.
- **Definition of done** — `agents_md_sha256` and `policy_sha256` freeze the
  project instructions and policy in effect. If AGENTS.md or the policy profile
  changes after the lock, prior evidence is invalidated because the inputs it
  was recorded against no longer match. This is what makes a run spec's
  `contract_lock_sha256` a meaningful freshness signal.

## Actor separation

The `locked_by` field records who authored the contract. When a slice
transitions to `in_progress`, `Conveyor.SliceLifecycle` checks that the
implementation `actor` differs from the brief's `locked_by`. This is the runtime
guard that prevents the same agent from both defining acceptance and
implementing against it, which would let an agent grade its own homework.

## Relationships

| Relationship  | Resource                      | Cardinality           | Notes                               |
| ------------- | ----------------------------- | --------------------- | ----------------------------------- |
| `slice`       | `Conveyor.Factory.Slice`      | belongs_to (required) | The slice whose contract is locked. |
| `agent_brief` | `Conveyor.Factory.AgentBrief` | belongs_to (required) | The brief frozen by the lock.       |

A slice can have many contract locks over its lifetime. Each
[run spec](run-spec.md) references a specific `contract_lock_sha256`, so
evidence is always checked against the lock that was in effect when the attempt
was planned.

## Contract forge and contract evolution

Contract locks are drafted by the contract forge, which assembles the digests
from plan requirements and agent briefs. When a slice's contract needs to change
(new requirements, revised acceptance criteria, updated AGENTS.md), a new
contract lock is created rather than editing the old one. The
[run spec](run-spec.md) then references the new lock's digest, and any in-flight
evidence recorded against the old lock is treated as stale. See
[contract management](../features/contract-management.md) for the full
lifecycle.

## Key source files

| File                                    | Purpose                                                         |
| --------------------------------------- | --------------------------------------------------------------- |
| `lib/conveyor/factory/contract_lock.ex` | Ash resource: digest fields, protected paths, relationships.    |
| `lib/conveyor/slice_lifecycle.ex`       | Enforces actor separation on slice start.                       |
| `lib/conveyor/factory/agent_brief.ex`   | The brief frozen by the lock.                                   |
| `lib/conveyor/factory/run_spec.ex`      | References `contract_lock_sha256` to bind an attempt to a lock. |

## Related pages

- [Primitives](index.md) — all foundational domain objects
- [Slice](slice.md) — the work unit the lock belongs to
- [Run spec](run-spec.md) — binds an attempt to a specific lock digest
- [Evidence](evidence.md) — checked against the locked acceptance criteria
- [Contract management](../features/contract-management.md) — contract lock
  lifecycle
- [Gate](../systems/gate.md) — how the gate uses the locked contract
