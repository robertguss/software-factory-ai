defmodule Conveyor.PlanningPilotAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-2/p2-b7/acceptance-gate.md"

  @criteria [
    "no selected contract is rewritten from scratch just to pass",
    "the selected set never changes after outcomes",
    "no failed selection is replaced",
    "every failure gets typed comparison/diagnosis/recovery",
    "unrelated ready Slices continue when one is parked",
    "the final report separates plan/compiler/context/implementation/evidence/adapter/operator failures",
    "the pilot covers graph/interface/risk/human-verification classes"
  ]

  test "P2-B7 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningPilotPlanTest",
          "PlanningPilotSelectionTest",
          "PlanningPilotExecutionTest",
          "PlanningPilotRetrospectiveTest",
          "PilotSelectionSchemaTest",
          "Conveyor.Planning.PilotSelection",
          "Conveyor.Planning.PilotExecution",
          "Conveyor.Planning.PilotRetrospective",
          "conveyor.pilot_selection@1",
          "test/fixtures/phase-2/p2-b7/pilot-plan.json"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
