defmodule Conveyor.AdapterConformanceFixturesTest do
  use ExUnit.Case, async: true

  @fixture_path "docs/phase-1.5/p15-b2/adapter-conformance-fixtures.json"

  @required_cases [
    "cancellation",
    "timeout",
    "malformed_events",
    "out_of_order_events",
    "duplicate_events",
    "crash",
    "credential_revocation",
    "missing_events"
  ]

  test "adapter conformance fixtures cover fail-closed degraded branches" do
    fixtures = @fixture_path |> File.read!() |> Jason.decode!()

    assert fixtures["schema_version"] == "conveyor.adapter_conformance_fixtures@1"
    assert fixtures["runner"] == "Conveyor.AgentRunner.MockDegraded"
    assert Enum.map(fixtures["cases"], & &1["key"]) == @required_cases

    for fixture <- fixtures["cases"] do
      assert fixture["expected"] == "fail_closed"
      assert fixture["finding"]["category"] == "adapter_conformance_failure"
      assert fixture["finding"]["branch"] == fixture["branch"]
      assert fixture["fixture_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    end
  end

  test "malformed and missing event fixtures cannot be treated as degraded success" do
    fixtures = @fixture_path |> File.read!() |> Jason.decode!()

    for key <- ["malformed_events", "missing_events"] do
      fixture = Enum.find(fixtures["cases"], &(&1["key"] == key))

      assert fixture["expected"] == "fail_closed"
      assert fixture["finding"]["severity"] == "blocking"
      assert fixture["finding"]["fail_closed"]
      assert fixture["allow_degraded_success"] == false
    end
  end
end
