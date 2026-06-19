defmodule Conveyor.PlanningCompilerAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-a2/acceptance-gate.md"

  @criteria [
    "compiler passes run in unit tests without Oban/Postgres/provider",
    "malformed proposals never materialize",
    "candidates remain visible and unblended",
    "identical pass inputs/version yield identical output + cache hit",
    "an authority-input change misses the cache",
    "reordering preserves unrelated IDs",
    "partial valid artifacts survive one failed candidate fragment"
  ]

  test "P2-A2 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningPassRegistryTest",
          "PlanningDecomposerTest",
          "PlanningDecompositionSelectionTest",
          "PlanningWorkGraphLoweringTest",
          "PlanningStableIdentityTest",
          "PlanningPassDiagnosticsTest",
          "conveyor.decomposition_selection@1"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
