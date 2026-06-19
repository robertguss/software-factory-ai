defmodule Conveyor.PlanningGraphAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-a3/acceptance-gate.md"

  @criteria [
    "likely-file overlap does not create a hard work edge",
    "provider/consumer schemas/versions resolve or block",
    "a human decision is not encoded as a fake Slice edge",
    "an unsafe atomicity split is rejected",
    "every authority artifact has derivation inputs",
    "low impact confidence fails wide",
    "structural simulation uses no fabricated economics"
  ]

  test "P2-A3 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningSliceDependencyTest",
          "PlanningInterfaceGraphTest",
          "PlanningSliceDecisionBlockTest",
          "PlanningPreliminaryVerificationTest",
          "PlanningArtifactInputIndexTest",
          "PlanningGraphAnalysesTest",
          "PlanningStructuralDryRunTest",
          "conveyor.slice_dependency@1",
          "conveyor.interface_contract@1",
          "conveyor.slice_interface_binding@1",
          "conveyor.slice_decision_block@1"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
