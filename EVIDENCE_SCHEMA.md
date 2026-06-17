# Conveyor Evidence Schema

Evidence is the trust primitive. A Slice is complete only when the conductor has
independent evidence, the reviewer can audit it, and the gate passes. Agent
claims are recorded as input, but they are not proof until the conductor reruns
or validates them.

The canonical machine schemas live under `docs/schemas/`, especially
`conveyor.evidence@1.json`, `conveyor.review@1.json`, `conveyor.gate@1.json`,
and `conveyor.run_bundle@1.json`. This document describes the human-facing
contract those schemas implement.

## Evidence Resource

The active `Evidence` resource records the proof surface for one RunAttempt:

| Field | Requirement |
| ----- | ----------- |
| `id` | Stable evidence identifier. |
| `run_attempt_id` | RunAttempt being proven. |
| `patch_set_id` | PatchSet applied to the clean gate workspace. |
| `changed_files[]` | Files changed by the accepted patch. |
| `diff_ref` | Content-addressed diff artifact. |
| `tool_invocation_refs[]` | Commands and tools attempted by agents or conductor. |
| `acceptance_results[]` | Acceptance criteria mapped to proof, failure, or blocker evidence. |
| `code_quality_result_ref` | Optional quality-signal artifact. |
| `risks[]` | Known residual risks. |
| `summary` | Short evidence summary suitable for dossier and PR draft. |
| `pr_body_ref` | Projected PR-body draft artifact. |

Evidence is generated from database records and content-addressed artifacts. It
is not copied from an agent final message unless independently checked.

## Machine Evidence

`evidence.json` uses `schema_version: "conveyor.evidence@1"` and must include:

| Field | Requirement |
| ----- | ----------- |
| `schema_version` | Exact schema version. |
| `run_spec_sha256` | Digest of the RunSpec that produced this evidence. |
| `slice_id` | Slice being proven. |
| `acceptance_criteria_evidence[]` | Criterion refs, status, and evidence refs. |
| `commands[]` | Rerun or recorded commands with status and log refs. |
| `artifacts[]` | Content-addressed artifact references. |
| `policy` | Policy profile and violations. |
| `known_risks[]` | Residual risks or empty array. |

Each `acceptance_criteria_evidence[]` entry must contain:

```json
{
  "criterion_ref": "ac-001",
  "status": "passed",
  "evidence_refs": ["tests/test_tasks.py::test_complete_task"]
}
```

`status` is one of `passed`, `failed`, or `blocked`. `evidence_refs[]` must not
be empty. Missing acceptance evidence fails RunCheck.

Each command entry must include the command key, argv, status, and stdout/stderr
references:

```json
{
  "key": "pytest",
  "argv": ["pytest", "-q"],
  "status": "passed",
  "stdout_ref": "commands/pytest.stdout.log",
  "stderr_ref": "commands/pytest.stderr.log"
}
```

Command evidence may point to redacted projections, but the manifest must retain
the digest relationship to the raw artifact when policy allows retaining raw
bytes.

## Tool Invocation Evidence

Every command or external tool call is recorded as a `ToolInvocation`:

| Field | Requirement |
| ----- | ----------- |
| `tool_name` | Tool or runner name. |
| `invocation_kind` | Command, file operation, adapter action, or policy-mediated tool. |
| `command_spec` | Normalized command spec used for policy and replay. |
| `policy_profile` | Policy applied to the invocation. |
| `cwd` | Workspace-relative current directory. |
| `env_keys[]` | Names of exposed environment variables, never secret values. |
| `network_mode` | Effective network mode. |
| `started_at`, `completed_at` | Timing metadata. |
| `exit_code`, `duration_ms` | Execution result. |
| `stdout_ref`, `stderr_ref` | Artifact references. |
| `output_sha256` | Digest of output bytes after classification. |
| `policy_decision` | Allow, deny, redact, quarantine, or require-human result. |
| `status` | Passed, failed, skipped, blocked, or cancelled. |

Adapter-reported tool calls are useful transcript evidence, but higher autonomy
requires conductor-mediated policy and independent gate execution.

## Human Dossier

`dossier.md` must be readable without opening Postgres. It is the reviewer and
human-operator view of the run:

```markdown
# Run Dossier: run_123

## Slice

## Requirement Traceability

## Summary

## Diff

## Acceptance Criteria -> Evidence

## Commands Re-run by Conductor

## Code Quality Delta

## Reviewer Verdict

## Gate Result

## Policy / Safety

## Known Risks

## Retrospective Notes
```

The dossier may contain prose and timestamps, but it must cite machine artifact
digests so the human-readable report can be checked against canonical evidence.

## PR-Body Draft

Phase 1 does not open or merge PRs automatically, but it still generates
`pr_body.md` so evidence quality matches the later L2 promise:

```markdown
## Task

Implements Slice `<id>` from requirement(s) `<REQ-...>`.

## Summary

## Acceptance Criteria

- [x] ...

## Verification

- [x] `pytest -q`
- [x] Code quality: no new high-risk findings
- [x] RunCheck: manifest/dossier valid
- [x] Reviewer: accepted

## Risk

## Agent

## Evidence

Run bundle: `<run_bundle_sha256>` Dossier digest: `<dossier_sha256>` Gate
digest: `<gate_result_sha256>`
```

The PR-body draft is an artifact, not merge authority. Merge remains manual in
Phase 1.

## Review And Gate Artifacts

`Review` records independent judgment:

| Field | Requirement |
| ----- | ----------- |
| `review_kind` | General, security, test, architecture, or configured kind. |
| `rubric_version` | Reviewer rubric version. |
| `dossier_sha256` | Dossier digest reviewed. |
| `decision` | Accepted, needs rework, or rejected. |
| `recommendation` | Merge, rework, ask human, or archive. |
| `summary` | Reviewer summary. |
| `findings[]` | Actionable findings with artifact refs and next actions. |
| `checks[]` | Rubric checks and pass/fail results. |

`GateResult` records deterministic policy:

| Field | Requirement |
| ----- | ----------- |
| `level` | Gate level, such as `slice`. |
| `passed` | Boolean final result. |
| `stages[]` | Workspace, diff, verification, policy, review, runcheck, canary, and artifact checks. |
| `false_negative?` | Optional gate-health signal. |
| `gate_version` | Gate implementation version. |
| `gate_code_sha256` | Gate code digest. |
| `policy_sha256` | Policy digest. |
| `contract_lock_sha256` | Contract lock digest. |
| `canary_suite_version` | Canary suite version used for freshness. |

The gate fails closed when required evidence is missing, blocked, redacted in a
policy-disallowed way, or inconsistent with the contract lock.

## Run Bundle

The projected run directory is represented by `manifest.json` using
`schema_version: "conveyor.run_bundle@1"`:

```json
{
  "schema_version": "conveyor.run_bundle@1",
  "run_attempt_id": "run_attempt_123",
  "entries": [
    {
      "path": "evidence.json",
      "kind": "evidence",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "size_bytes": 12042,
      "sensitivity": "public",
      "schema_version": "conveyor.evidence@1"
    }
  ],
  "bundle_root_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
}
```

Typical Phase 1 projections:

```text
.conveyor/runs/run_attempt_<id>/
  manifest.json
  dossier.md
  evidence.json
  review.json
  gate.json
  provenance.intoto.json
  sbom.cyclonedx.json
  pr_body.md
  diff.patch
  commands/
    pytest.stdout.log
    pytest.stderr.log
  codescent/
    before.json
    after.json
  canary/
    mutants.json
```

`bundle_root_sha256` is computed from canonical manifest entries. Generated
timestamps, host paths, and non-deterministic ordering are excluded from the
root digest. Human-readable files may contain timestamps, but the machine
manifest must identify which fields are excluded from deterministic replay.

## Redaction And Retention

Before evidence is displayed or exported, `Security.Redactor` scans prompts,
tool outputs, command logs, diffs, environment metadata, and generated reports.

Rules:

- Raw command output is classified before projection.
- Sensitive raw artifacts are marked `sensitive` or `quarantined` and are never
  included in `.conveyor/runs/<run_attempt_id>/`.
- Exported artifacts are separate redacted projections with their own digest.
- Manifests record `raw_sha256` when policy permits retaining raw bytes and
  `redacted_sha256` for exported bytes.
- A blocked secret finding prevents gate success unless policy explicitly allows
  redacted continuation.
- Garbage collection must not delete a blob referenced by a database record
  unless RetentionPolicy allows it, and every deletion writes a LedgerEvent
  tombstone.

The gate must never compare redacted artifact bytes against raw command-output
digests without knowing which digest is being checked.
