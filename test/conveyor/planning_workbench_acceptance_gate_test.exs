defmodule Conveyor.PlanningWorkbenchAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-2/p2-b5/acceptance-gate.md"

  @criteria [
    "the approver identifies every high-impact claim/constraint/waiver",
    "candidate differences are visible",
    "the preview states grants/roots/contracts/tests/attempts affected",
    "changing authority bytes invalidates exact dependent approvals",
    "a review erratum follows review policy",
    "every action creates normal domain records/events"
  ]

  test "P2-B5 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningWorkbenchShellTest",
          "PlanningWorkbenchViewsTest",
          "PlanningWorkbenchActionsTest",
          "PlanningImpactPreviewTest",
          "PlanningHumanApprovalBindingTest",
          "ChangeSetSchemaTest",
          "ApprovalPolicySchemaTest",
          "ApprovalSetSchemaTest",
          "Conveyor.Planning.WorkbenchShell",
          "Conveyor.Planning.WorkbenchViews",
          "Conveyor.Planning.WorkbenchActions",
          "Conveyor.Planning.ImpactPreview",
          "Conveyor.Planning.HumanApprovalBinding",
          "conveyor.change_set@1",
          "conveyor.approval_policy@1",
          "conveyor.approval_set@1"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
