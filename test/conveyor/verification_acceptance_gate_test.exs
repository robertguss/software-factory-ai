defmodule Conveyor.VerificationAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-1.5/p15-b4/acceptance-gate.md"

  @criteria [
    "readiness is per obligation, not TestPack aggregate",
    "required flake/non-hermetic/vacuity blocks",
    "quarantine cannot satisfy an obligation",
    "active waiver requires human decision, owner, expiry, controls, max autonomy",
    "human-observed evidence is distinct from machine evidence",
    "repeated TestIntegrityRun samples are permitted and comparable"
  ]

  test "P15-B4 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "VerificationResourcesTest",
          "EvidenceRequirementTest",
          "TestIntegritySentinelTest",
          "FalsifierSeamTest",
          "VerificationCockpitTest",
          "EvidenceKernelResourcesTest"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
