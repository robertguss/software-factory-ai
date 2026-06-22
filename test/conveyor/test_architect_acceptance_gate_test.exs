defmodule Conveyor.TestArchitectAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-2/p2-b2/acceptance-gate.md"

  @criteria [
    "the Test Architect cannot edit source",
    "tests map to obligations/ACs and base reasons",
    "a dropped falsifier blocks",
    "`boundary_unclear` routes to split/clarify",
    "universal mutation is required only with a legitimate reference",
    "human-only evidence remains human-only",
    "weak evidence routes to its author, not the implementer"
  ]

  test "P2-B2 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "TestArchitectWorkspaceTest",
          "TestArchitectArtifactsTest",
          "TestArchitectFalsifierPreservationTest",
          "OracleFeasibilityTest",
          "TestArchitectIntegrityGateTest",
          "HumanVerificationTest",
          "ContractAuditTest",
          "Conveyor.TestArchitect.Workspace",
          "Conveyor.TestArchitect.IntegrityGate"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
