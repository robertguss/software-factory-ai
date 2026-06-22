defmodule Conveyor.PlanningAmendmentAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-2/p2-b6/acceptance-gate.md"

  @criteria [
    "the implementer cannot self-declare nonmaterial",
    "acceptance/obligation/decision/hard-constraint/scope/compatibility/waiver weakening is material",
    "unaffected digests remain only when derivation proves safety",
    "a shared-interface change invalidates consumers",
    "a review-only correction preserves the lock",
    "old evidence remains interpretable",
    "negotiation round limits hold"
  ]

  test "P2-B6 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningPlanAmendmentsTest",
          "PlanningMaterialityPolicyTest",
          "PlanningSelectiveRecompilationTest",
          "PlanningSelectiveInvalidationTest",
          "PlanningAmendmentEnforcementTest",
          "PlanAmendmentProposalSchemaTest",
          "ManualInterventionArtifactSchemaTest",
          "Conveyor.Planning.PlanAmendments",
          "Conveyor.Planning.MaterialityPolicy",
          "Conveyor.Planning.SelectiveRecompilation",
          "Conveyor.Planning.SelectiveInvalidation",
          "Conveyor.Planning.AmendmentEnforcement",
          "conveyor.plan_amendment_proposal@1",
          "conveyor.manual_intervention_artifact@1"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
