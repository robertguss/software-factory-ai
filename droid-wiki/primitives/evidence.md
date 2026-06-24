# Evidence

Evidence is the independent, machine-checkable proof that a slice met its
acceptance criteria. In Conveyor, agent claims are input, not proof. The
evidence resource aggregates what the stations actually observed: changed files,
a diff reference, tool invocation references, acceptance results, a code quality
result reference, and risk assessments. The gate reads this record to decide
whether a slice passes without human review.

The resource lives in `lib/conveyor/factory/evidence.ex` and is persisted in the
`evidence` Postgres table. Unlike slice and run attempt, evidence has no state
machine: it is an aggregated snapshot written once the evidence recorder station
has collected its inputs.

## Fields

| Field                     | Type             | Notes                                                                                                                            |
| ------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `id`                      | UUID             | Primary key.                                                                                                                     |
| `changed_files`           | array of strings | Required, default `[]`. Files changed by the attempt.                                                                            |
| `diff_ref`                | string           | Required. Content-addressed reference to the diff (blob store digest).                                                           |
| `tool_invocation_refs`    | array of strings | Required, default `[]`. References to the recorded tool invocations that produced the evidence.                                  |
| `acceptance_results`      | array of maps    | Required, default `[]`. Per-criterion acceptance results mapping each acceptance criterion to a pass/fail and supporting detail. |
| `code_quality_result_ref` | string           | Optional. Reference to the code quality run result (e.g. CodeScent/local Python adapter output).                                 |
| `risks`                   | array of maps    | Required, default `[]`. Risk assessments flagged during evidence recording.                                                      |
| `summary`                 | string           | Required. Human-readable summary of the evidence, cited by the dossier.                                                          |
| `pr_body_ref`             | string           | Optional. Reference to the drafted PR body produced from the evidence.                                                           |
| `run_attempt_id`          | UUID             | Required. The run attempt this evidence belongs to.                                                                              |
| `patch_set_id`            | UUID             | Required. The patch set the evidence verifies.                                                                                   |

## What evidence captures

Evidence is the bridge between what an agent did and what the gate can verify.
Each field ties an agent's work back to the locked contract:

- **`acceptance_results`** maps each acceptance criterion from the
  [contract lock](contract-lock.md) to a machine-checked result. This is the
  core of the determinism boundary: the gate does not trust the agent's summary,
  it reads these structured results.
- **`tool_invocation_refs`** point at `Conveyor.Factory.ToolInvocation` records,
  which carry the normalized command spec, the policy decision, and the output
  digest. This makes every claim traceable to a recorded, policy-vetted tool
  call.
- **`diff_ref`** is a content-addressed reference into the blob store, so the
  exact diff evaluated by the gate is pinned and replayable.
- **`code_quality_result_ref`** links to the code quality analysis run on the
  diff, providing the quality delta the reviewer and gate consider.
- **`risks`** records any risk assessments surfaced during evidence recording,
  feeding the reviewer and retrospective.

## Relationships

| Relationship  | Resource                      | Cardinality           | Notes                                          |
| ------------- | ----------------------------- | --------------------- | ---------------------------------------------- |
| `run_attempt` | `Conveyor.Factory.RunAttempt` | belongs_to (required) | The attempt whose work this evidence verifies. |
| `patch_set`   | `Conveyor.Factory.PatchSet`   | belongs_to (required) | The patch set being verified.                  |

Evidence is written by the evidence recorder station and consumed by the
reviewer and gate. It is one of the records that feeds the
[run bundle](run-attempt.md) dossier, which cites machine artifact digests so a
human reader can audit the same evidence the gate used.

## Link to evidence recording

The evidence resource is the persisted shape; the process that populates it is
the evidence recording system, which runs as a station in the pipeline. See
[evidence recording](../systems/evidence-recording.md) for how tool invocations,
diffs, and acceptance results are gathered and written into this record.

## Key source files

| File                                       | Purpose                                                   |
| ------------------------------------------ | --------------------------------------------------------- |
| `lib/conveyor/factory/evidence.ex`         | Ash resource: fields and relationships.                   |
| `lib/conveyor/factory/tool_invocation.ex`  | Recorded tool calls referenced by `tool_invocation_refs`. |
| `lib/conveyor/factory/patch_set.ex`        | Patch set verified by the evidence.                       |
| `lib/conveyor/factory/code_quality_run.ex` | Code quality run referenced by `code_quality_result_ref`. |

## Related pages

- [Primitives](index.md) — all foundational domain objects
- [Run attempt](run-attempt.md) — the attempt evidence belongs to
- [Contract lock](contract-lock.md) — the acceptance criteria evidence is
  checked against
- [Evidence recording](../systems/evidence-recording.md) — how evidence is
  captured
- [Gate](../systems/gate.md) — how the gate consumes evidence
- [Station pipeline](../features/station-pipeline.md) — where the evidence
  recorder sits
