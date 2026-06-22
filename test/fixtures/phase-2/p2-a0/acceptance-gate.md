# P2-A0 Acceptance Gate

Status: pass.

## Evidence

| Exit criterion | Evidence |
| --- | --- |
| formatting-only edits need not create semantic revisions | `PlanningRevisionLifecycleTest` covers source snapshot import where formatting-only content changes create snapshots without publishing a new semantic revision. |
| published revisions are immutable | `PlanningRevisionLifecycleTest` rejects mutation of a published `PlanRevision` and requires a new revision for semantic contract changes. |
| copied/observed/derived provenance is assigned deterministically | `PlanningClaimsTest` covers explicit human claims, repo-observed anchors, deterministic derived claims, and coverage inheritance without trusting model self-reporting. |
| unmatched residuals are explicitly inferred | `PlanningClaimsTest` emits residual `agent_inferred` claims only for unmatched plan material. |
| hard constraints cannot be scored away | `PlanningConstraintsTest` enforces hard-constraint precedence over soft scoring and reports violated/at-risk/not-assessed outcomes. |
| same canonical input yields the same semantic/pass inputs | `PlanningSpecTest` pins deterministic pass/spec digests, and `PlanningCompatibilityFixturesTest` proves reordered semantic equivalents share the same pass graph digest. |

## Artifacts

- `test/fixtures/phase-2/p2-a0/schema-pass-compatibility.json`
- `lib/conveyor/planning/admission.ex`
- `lib/conveyor/planning/revision_lifecycle.ex`
- `lib/conveyor/planning/claims.ex`
- `lib/conveyor/planning/constraints.ex`
- `lib/conveyor/planning/planning_spec.ex`

## Verification

- `PlanningAdmissionTest`
- `PlanningRevisionLifecycleTest`
- `PlanningClaimsTest`
- `PlanningConstraintsTest`
- `PlanningSpecTest`
- `PlanningCompatibilityFixturesTest`
- `MIX_ENV=test mix compile --warnings-as-errors`
