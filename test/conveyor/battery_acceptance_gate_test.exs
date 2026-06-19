defmodule Conveyor.BatteryAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-1.5/p15-b1/acceptance-gate.md"

  @criteria [
    "fixture validation precedes provider calls",
    "poison pill yields `battery_fixture_failure`",
    "safety-trajectory violations are detected even when the terminal outcome is safe",
    "failed samples cannot be omitted/replaced",
    "scorer-only metadata never reaches RoleViews/prompts/workspaces/projections",
    "threshold/stop-rule change creates a new policy digest",
    "provider/infra failures are separated from quality"
  ]

  test "P15-B1 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "BatteryFixtureBoundaryTest",
          "BatteryTraceAssertionsTest",
          "BatteryCorpusManifestTest",
          "BatterySamplingPolicyTest",
          "RunBatteryTest"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
