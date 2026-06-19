defmodule Conveyor.PlanningPromptBudgetAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-b4/acceptance-gate.md"

  @criteria [
    "critical-context drop fails before the provider",
    "a review-only change does not alter authority roots",
    "a semantic/waiver/policy change alters the correct roots",
    "the approval record is not included in the signed root",
    "the summary cannot hide a blocker",
    "UI/static/CLI derive the same bundle"
  ]

  test "P2-B4 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningContextAssemblyTest",
          "PlanningPromptDryCompileTest",
          "PlanningLayeredRootsTest",
          "PlanningRootAttestationsTest",
          "PlanningFactoryChronicleTest",
          "PlanningBundleSchemaTest",
          "Conveyor.Planning.ContextAssemblyManifest",
          "Conveyor.Planning.PromptDryCompile",
          "Conveyor.Planning.LayeredRoots",
          "Conveyor.Planning.RootAttestations",
          "Conveyor.Planning.FactoryChronicle",
          "conveyor.planning_bundle@1"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
