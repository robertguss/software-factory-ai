defmodule Conveyor.BatteryReleaseReportTest do
  use ExUnit.Case, async: true

  alias Conveyor.Battery.ReleaseReport

  test "canonical blockers remain visible even when a source summary omits them" do
    report =
      ReleaseReport.build([
        %{
          source_id: "trace_assertions",
          summary: "Trace assertions complete.",
          failed_cases: [
            %{case_id: "canonical-blocker", reason: "policy_blocked"}
          ],
          excluded_cases: []
        }
      ])

    assert report["schema_version"] == "conveyor.battery_release_report@1"
    assert report["complete?"] == true

    assert report["canonical_blockers"] == [
             %{
               "source_id" => "trace_assertions",
               "case_id" => "canonical-blocker",
               "reason" => "policy_blocked"
             }
           ]
  end

  test "release report includes every excluded case by source" do
    report =
      ReleaseReport.build([
        %{
          source_id: "behavior_oracle",
          summary: "Bounded oracle run.",
          failed_cases: [],
          excluded_cases: [
            %{case_id: "unavailable-fixture", reason: "external_dependency_missing"}
          ]
        }
      ])

    assert report["excluded_cases"] == [
             %{
               "source_id" => "behavior_oracle",
               "case_id" => "unavailable-fixture",
               "reason" => "external_dependency_missing"
             }
           ]
  end
end
