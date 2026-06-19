defmodule Conveyor.PlanningAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-a0/acceptance-gate.md"

  @criteria [
    "formatting-only edits need not create semantic revisions",
    "published revisions are immutable",
    "copied/observed/derived provenance is assigned deterministically",
    "unmatched residuals are explicitly inferred",
    "hard constraints cannot be scored away",
    "same canonical input yields the same semantic/pass inputs"
  ]

  test "P2-A0 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningAdmissionTest",
          "PlanningRevisionLifecycleTest",
          "PlanningClaimsTest",
          "PlanningConstraintsTest",
          "PlanningSpecTest",
          "PlanningCompatibilityFixturesTest"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
