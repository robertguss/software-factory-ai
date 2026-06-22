defmodule Conveyor.PlanningInterrogationAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-2/p2-a1/acceptance-gate.md"

  @criteria [
    "contradiction/unbounded/missing-decision/oracle fixtures are caught",
    "a clean plan produces no hard questions",
    "injection cannot suppress a required question",
    "source observations cite exact immutable anchors or `unknown`",
    "extractor failure does not invent impact",
    "budget exhaustion follows explicit policy",
    "critical context is not silently omitted"
  ]

  test "P2-A1 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningStructuralAuditTest",
          "PlanningInterrogatorTest",
          "PlanningHumanDecisionWorkflowTest",
          "PlanningRepositoryInventoryTest",
          "PlanningScoutTest",
          "PlanningContextAssemblyTest",
          "PlanningCodeImpactOverlayTest",
          "ContextGroundTruthFixturesTest",
          "conveyor.planning_run@1",
          "conveyor.plan_interrogation@1"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
