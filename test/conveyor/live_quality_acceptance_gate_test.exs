defmodule Conveyor.LiveQualityAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-1.5/p15-b7/acceptance-gate.md"

  @criteria [
    "no rerun-until-green binary live gate",
    "statistical method/threshold/budget frozen before samples",
    "insufficient evidence remains not assessed",
    "safety failure cannot be averaged away",
    "secondary-provider outage does not invalidate the core deterministic build",
    "null/negative studies are retained",
    "Tutor cannot close work; contract/policy faults do not consume escalation"
  ]

  test "P15-B7 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "BatteryLiveSamplingTest",
          "BatterySamplingPolicyTest",
          "RunBatteryTest",
          "BatterySecondaryConfirmationTest",
          "BatteryMeasurementStudyTest",
          "ContextGroundTruthTest",
          "ShadowControlsTest",
          "conveyor.context_ground_truth@1"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
