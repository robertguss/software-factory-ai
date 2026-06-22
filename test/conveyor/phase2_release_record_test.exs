defmodule Conveyor.Phase2ReleaseRecordTest do
  use ExUnit.Case, async: true

  @record_path "test/fixtures/phase-2/p2-b8/release-record.md"

  test "release record publishes limitations debt grants waivers and residual risks" do
    record = File.read!(@record_path)

    for section <- [
          "Limitations",
          "Decision Debt",
          "Active Grants",
          "WaiverBudget",
          "Active Waivers",
          "Residual Risks"
        ] do
      assert record =~ section
    end

    for required_field <- [
          "owner",
          "scope",
          "expiry",
          "compensating controls",
          "autonomy effect",
          "qualification_grant:sha256",
          "offline-only sample",
          "no production deployment authority"
        ] do
      assert record =~ required_field
    end

    refute record =~ "TBD"
  end
end
