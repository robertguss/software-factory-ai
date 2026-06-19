defmodule Conveyor.PlanningSliceDecisionBlockTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SliceDecisionBlock

  test "blocks slices through decision graph without creating fake work edges" do
    result =
      SliceDecisionBlock.analyze(%{
        blocks: [
          %{slice_key: "SLC-API", human_decision_ref: "DEC-COMPAT", reason: "Choose API compatibility strategy"},
          %{slice_key: "SLC-UI", human_decision_ref: "DEC-COPY", reason: "Approve final copy"}
        ],
        human_decisions: [
          %{decision_ref: "DEC-COMPAT", state: "open"},
          %{decision_ref: "DEC-COPY", state: "answered"}
        ]
      })

    assert result.status == :blocked
    assert result.fake_work_edges == []

    assert result.decision_blocks == [
             %{
               slice_key: "SLC-API",
               human_decision_ref: "DEC-COMPAT",
               reason: "Choose API compatibility strategy",
               decision_state: :open,
               status: :blocked
             },
             %{
               slice_key: "SLC-UI",
               human_decision_ref: "DEC-COPY",
               reason: "Approve final copy",
               decision_state: :answered,
               status: :ready
             }
           ]

    assert result.diagnostics == [
             %{
               rule_key: "slice_decision_unresolved",
               severity: :blocking,
               subject_key: "SLC-API -> DEC-COMPAT"
             }
           ]
  end

  test "reports missing human decisions for declared decision blocks" do
    result =
      SliceDecisionBlock.analyze(%{
        blocks: [
          %{slice_key: "SLC-API", human_decision_ref: "DEC-MISSING", reason: "Missing decision"}
        ],
        human_decisions: []
      })

    assert result.status == :blocked

    assert result.diagnostics == [
             %{
               rule_key: "slice_decision_missing",
               severity: :blocking,
               subject_key: "SLC-API -> DEC-MISSING"
             }
           ]
  end
end
