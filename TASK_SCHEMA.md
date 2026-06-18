# Conveyor Task Schema

This document defines the human-facing task contract for Phase 0/1. It describes
what a Slice and AgentBrief must contain before Conveyor can build a RunSpec,
prompt an implementer, and later verify the work. Machine artifacts use the
versioned JSON Schemas under `docs/schemas/`; this document is the readable
contract those schemas and resources implement.

## Task Contract

A Conveyor task is a locked implementation packet, not a loose instruction. The
minimum Phase 1 task surface is:

- `Plan`: the imported human-approved source contract.
- `Requirement`: stable requirement rows derived from the plan.
- `HumanDecision`: explicit user decisions that constrain interpretation.
- `Epic`: a grouping of related Slices.
- `Slice`: one bounded implementation unit.
- `AgentBrief`: the locked implementer contract for exactly one Slice.
- `ContractLock`: hashes that prove which contract inputs were used.
- `TestPack`: locked acceptance tests and fixtures.
- `VerificationSuite`: commands the conductor can rerun independently.

Future concepts may appear as typed embedded JSON or artifacts, but they do not
become active tables until a Phase 0/1 workflow needs independent lifecycle,
permissions, querying, retention, or gate behavior.

## Slice Fields

`Slice` is the schedulable unit of work:

| Field | Requirement |
| ----- | ----------- |
| `id` | Stable identifier. |
| `epic_id` | Parent Epic. |
| `title` | Short task title. |
| `position` | Ordering within the Epic. |
| `risk` | Planned risk level used by review and gate policy. |
| `state` | Lifecycle state managed by the conductor. |
| `autonomy_level` | Maximum requested autonomy for this Slice. |
| `source_refs[]` | Plan, requirement, and decision references. |
| `likely_files[]` | Advisory paths from the plan or ContextScout. |
| `conflict_domains[]` | Later scheduler hints; collected in Phase 1 even for a single Slice. |
| `diff_policy_id?` | Optional path and change-budget policy. |

A Slice is not ready for implementation until it has a locked AgentBrief,
acceptance criteria, required tests or a documented reason why tests are not
possible, verification commands, and an applicable policy profile.

## AgentBrief Fields

`AgentBrief` is the implementation contract. A prompt may quote or transform
it, but the brief digest remains the source of truth.

| Field | Requirement |
| ----- | ----------- |
| `id` | Stable brief identifier. |
| `slice_id` | The Slice this brief authorizes. |
| `version` | Monotonic version for the same Slice. |
| `current_behavior` | Observable current behavior or missing behavior. |
| `desired_behavior` | Target behavior stated in product terms. |
| `key_interfaces` | APIs, modules, commands, files, or UX surfaces likely affected. |
| `out_of_scope` | Explicit boundaries the implementer must not cross. |
| `risk` | Risk classification used by ReviewPolicy and GateResult. |
| `acceptance_criteria[]` | Concrete criteria mapped to requirements and evidence. |
| `required_tests[]` | Locked test references, fixtures, or required test intent. |
| `verification_commands[]` | Command specs the conductor can rerun independently. |
| `non_goals[]` | Things that should not be solved in this Slice. |
| `locked_at` | Timestamp of contract lock. |
| `locked_by` | Actor that locked the contract. |
| `contract_sha256` | Digest over the normalized brief contract. |

An AgentBrief is invalid if it relies on implied behavior, contains conflicting
authority, lacks concrete acceptance criteria, omits verification, or asks the
agent to change policy, locked tests, protected paths, or project instructions.

## Acceptance Criteria

Each `acceptance_criteria[]` entry must be concrete enough for a reviewer and
the gate to map it to evidence:

```json
{
  "id": "ac-001",
  "text": "PATCH /tasks/{id} with completed=true returns 200 and updated task",
  "kind": "behavioral",
  "requirement_refs": ["REQ-003"],
  "required_test_refs": ["tests/test_tasks.py::test_complete_task"],
  "evidence_status": "missing",
  "evidence_refs": []
}
```

Rules:

- `id` is stable within the brief and is the join key used by evidence.
- `text` states observable behavior, not implementation preference.
- `kind` classifies the proof surface, such as `behavioral`, `regression`,
  `security`, `quality`, `migration`, `docs`, or `policy`.
- `requirement_refs[]` links back to Plan/Requirement/HumanDecision source.
- `required_test_refs[]` names locked tests, fixtures, or verification probes.
- `evidence_status` starts as `missing` and may become `passed`, `failed`, or
  `skipped` only after independent verification.
- `evidence_refs[]` is empty before the run and later points to evidence,
  command output, reviews, gate stages, or blocker artifacts.

Skipped criteria require an explicit finding and cannot pass the gate unless
project policy allows the skip.

## Required Tests And Verification Commands

`required_tests[]` names what must be proven. `verification_commands[]` names how
the conductor reruns proof. Every required command is represented by a command
spec:

```json
{
  "key": "pytest",
  "argv": ["pytest", "-q"],
  "cwd": ".",
  "profile": "verify",
  "required": true,
  "timeout_ms": 120000,
  "network": "none",
  "env_allowlist": ["PYTHONPATH"],
  "output_limit_bytes": 2000000,
  "repeat": 1,
  "flake_policy": "fail_closed",
  "infra_retry_policy": { "max_retries": 1, "retry_on": ["container_start_failed"] },
  "result_format": "junit",
  "result_ref": "artifacts/test-results/pytest.xml",
  "result_adapter": "Conveyor.TestResultAdapter.JUnit"
}
```

Command specs must be deterministic enough to rerun in a clean gate workspace.
They must not depend on ambient credentials, undeclared network access,
interactive input, local absolute paths, or host-specific state.

## Contract Lock

`ContractLock` records the digests that make a run interpretable later:

| Field | Meaning |
| ----- | ------- |
| `agent_brief_id` | Locked brief. |
| `plan_contract_sha256` | Normalized plan contract digest. |
| `brief_sha256` | Normalized AgentBrief digest. |
| `acceptance_criteria_sha256` | Digest over AC text and mappings. |
| `required_tests_sha256` | Digest over locked tests and test refs. |
| `test_pack_sha256` | Digest over the TestPack artifact set. |
| `verification_commands_sha256` | Digest over command specs. |
| `agents_md_sha256` | Digest over applied project instructions. |
| `policy_sha256` | Digest over the policy profile. |
| `protected_path_globs[]` | Paths the run must not change. |
| `locked_at`, `locked_by` | Lock provenance. |

Any change to the brief, acceptance criteria, required tests, TestPack,
verification commands, AGENTS.md, policy, DiffPolicy, autonomy ceiling, or
protected paths requires a new lock and a new RunSpec.

## Readiness Rules

A task can move to implementation only when:

- The Slice is narrow enough for one bounded implementation attempt.
- The AgentBrief contains current behavior, desired behavior, key interfaces,
  out-of-scope boundaries, risk, acceptance criteria, required tests, and
  verification commands.
- Every acceptance criterion maps to at least one requirement or human decision.
- Required tests and command specs are locked or a finding explains the blocker.
- ContractLock digests are present.
- DiffPolicy and policy profile are compatible with the requested autonomy
  level.
- The conductor can build a RunSpec from the locked contract.

If any of these checks fail, the task should remain in planning or readiness
review. The agent should not infer missing contract terms during implementation.
