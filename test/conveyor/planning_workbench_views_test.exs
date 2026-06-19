defmodule Conveyor.PlanningWorkbenchViewsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.WorkbenchViews

  test "projects every core workbench view into operator lanes without authority effects" do
    projection =
      WorkbenchViews.project(%{
        claims: [%{id: "claim-1", lane: "intent"}],
        constraints: [%{id: "constraint-1", lane: "intent"}],
        candidates: [%{id: "candidate-1", lane: "risk_recovery"}],
        work_graph: [%{id: "edge-1", lane: "traceability"}],
        interfaces: [%{id: "interface-1", lane: "traceability"}],
        decision_blocks: [%{id: "decision-1", lane: "risk_recovery"}],
        obligations: [%{id: "obligation-1", lane: "traceability"}],
        derivations: [%{id: "derivation-1", lane: "traceability"}],
        diffs: [%{id: "diff-1", lane: "code_impact"}],
        approvals: [%{id: "approval-1", lane: "risk_recovery"}]
      })

    assert projection["schema_version"] == "conveyor.plan_workbench_views@1"
    assert projection["authority_effect"] == "none"
    assert projection["projection_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/

    assert projection["view_order"] == [
             "claims",
             "constraints",
             "candidates",
             "work_graph",
             "interfaces",
             "decision_blocks",
             "obligations",
             "derivations",
             "diffs",
             "approvals"
           ]

    assert projection["lanes"]["intent"] == ["claim-1", "constraint-1"]

    assert projection["lanes"]["traceability"] == [
             "derivation-1",
             "edge-1",
             "interface-1",
             "obligation-1"
           ]

    assert projection["lanes"]["risk_recovery"] == [
             "approval-1",
             "candidate-1",
             "decision-1"
           ]

    assert projection["lanes"]["code_impact"] == ["diff-1"]
    assert projection["views"]["claims"]["items"] == [%{"id" => "claim-1", "lane" => "intent"}]
  end

  test "missing core view data is represented as empty views, not omitted views" do
    projection = WorkbenchViews.project(%{claims: [%{id: "claim-1"}]})

    assert Map.has_key?(projection["views"], "approvals")
    assert projection["views"]["approvals"]["items"] == []
    assert projection["views"]["claims"]["count"] == 1
  end
end
