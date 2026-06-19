# P2-B5 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: minimal Qualification Cockpit and Plan Workbench shell, core Workbench
views, structured operator actions, deterministic impact preview, exact-root
human approval binding, and the ChangeSet/ApprovalPolicy/ApprovalSet schemas.

## Exit Criteria

### the approver identifies every high-impact claim/constraint/waiver

Evidence:

- `Conveyor.Planning.WorkbenchShell` exposes the Qualification Cockpit panels
  for grants, samples, invariants, adapters, health, replay, obligations,
  budgets, and stop state with static/headless parity.
- `PlanningWorkbenchShellTest` proves the shell includes every Cockpit panel and
  blocks when static/headless bundle digests differ.
- `Conveyor.Planning.WorkbenchViews` keeps claims, constraints, decision blocks,
  obligations, approvals, and related artifacts in explicit operator lanes.
- `PlanningWorkbenchViewsTest` proves high-impact intent/risk/recovery view
  data is present and missing view families render as empty views rather than
  disappearing.

### candidate differences are visible

Evidence:

- `Conveyor.Planning.WorkbenchViews` projects candidate records as a first-class
  view in the risk/recovery lane.
- `PlanningWorkbenchViewsTest` proves candidate entries remain visible in the
  lane model.
- `Conveyor.Planning.WorkbenchActions` includes `select_candidate` in its
  explicit action catalog and compiles selection to a `conveyor.change_set@1`
  replacement operation at `/candidate_selection_id`.
- `PlanningWorkbenchActionsTest` proves the selected candidate value and reason
  are carried in the emitted ChangeSet.

### the preview states grants/roots/contracts/tests/attempts affected

Evidence:

- `Conveyor.Planning.ImpactPreview` wraps the deterministic invalidation
  reducer into operator-facing categories for invalidated approvals/roots,
  regenerated contracts/interfaces, revalidated TestPacks and obligations,
  reusable locks, new RunSpecs/attempts, and grant impact.
- `PlanningImpactPreviewTest` proves grant impact, approval roots, contracts,
  obligations, reusable locks, and new RunSpecs are visible, and that low
  confidence fails wide with an `impact_confidence_low` warning.

### changing authority bytes invalidates exact dependent approvals

Evidence:

- `Conveyor.Planning.ImpactPreview` surfaces invalidated approval roots from the
  underlying authority/invalidation indexes.
- `PlanningImpactPreviewTest` proves changed authority-linked inputs invalidate
  the exact Epic approval root.
- `Conveyor.Planning.HumanApprovalBinding` binds approvals to the exact shared
  authority root, selected Epic authority roots, and review root shown to the
  approver.
- `PlanningHumanApprovalBindingTest` proves only the selected Epic root is bound
  and the resulting `conveyor.approval_set@1` is schema-valid.

### a review erratum follows review policy

Evidence:

- `conveyor.approval_policy@1` records role requirements, threshold,
  acknowledgement keys, separation-of-duties rules, and expiry policy.
- `ApprovalPolicySchemaTest` proves threshold-one local policy is valid and a
  policy without `threshold` is rejected.
- `Conveyor.Planning.HumanApprovalBinding` requires the exact review root and
  records accepted warnings, assumptions, waivers, autonomy ceiling, and
  signature status alongside the authority roots.
- `PlanningHumanApprovalBindingTest` proves missing review roots block approval
  binding.

### every action creates normal domain records/events

Evidence:

- `Conveyor.Planning.WorkbenchActions` compiles every structured operator action
  to an append-only `conveyor.change_set@1`; it does not mutate canonical rows
  in place.
- `PlanningWorkbenchActionsTest` proves the action catalog includes approve,
  reject, select, accept/reject claim/assumption/waiver, split/merge,
  reclassify, constraint/interface/compatibility change, human verification,
  strengthen contract, cheapest-wrong display, rerun affected, preview
  invalidation, amendment, draft, stop, and resume actions.
- `ChangeSetSchemaTest` proves ChangeSet requires subject, base revision
  digest, operations, preconditions, materiality labels, impact preview ref,
  digest, and status.
- `ApprovalSetSchemaTest` proves approval sets bind subject authority roots,
  review root, policy digest, approval ids, revocation events, and threshold
  satisfaction.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `PlanningWorkbenchShellTest` | missing Cockpit panels, static/headless bundle mismatch | none |
| `PlanningWorkbenchViewsTest` | hidden candidate/claim/constraint/waiver view families | none |
| `PlanningWorkbenchActionsTest` | action mutates directly instead of emitting ChangeSet, missing base preconditions | none |
| `PlanningImpactPreviewTest` | grant/root/contract/test/attempt impacts omitted, low confidence not fail-wide | none |
| `PlanningHumanApprovalBindingTest` | approval not bound to exact roots, missing review root accepted | none |
| `ChangeSetSchemaTest` | ChangeSet missing preconditions or required mutation fields | none |
| `ApprovalPolicySchemaTest` | approval policy missing threshold | none |
| `ApprovalSetSchemaTest` | approval set missing threshold satisfaction or root binding fields | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B5 test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `jq empty` for the P2-B5 schemas and examples.
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
