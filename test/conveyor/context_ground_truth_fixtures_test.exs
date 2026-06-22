defmodule Conveyor.ContextGroundTruthFixturesTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContextGroundTruth

  @fixture_path "test/fixtures/phase-2/p2-a1/context-ground-truth-fixtures.json"

  test "battery-only labelled fixtures report precision recall while unlabelled cases use proxies" do
    manifest = @fixture_path |> File.read!() |> Jason.decode!()

    assert manifest["schema_version"] == "conveyor.context_ground_truth_fixtures@1"
    assert manifest["scope"] == "battery_only"

    labelled_report =
      manifest
      |> Map.fetch!("labelled_cases")
      |> hd()
      |> ContextGroundTruth.evaluate()

    assert labelled_report["labelled"] == true
    assert is_float(labelled_report["selected_context_precision"])
    assert is_float(labelled_report["necessary_context_recall"])

    unlabelled_report =
      manifest
      |> Map.fetch!("unlabelled_proxy_cases")
      |> hd()
      |> ContextGroundTruth.evaluate()

    assert unlabelled_report["labelled"] == false
    assert unlabelled_report["selected_context_precision"] == nil
    assert unlabelled_report["necessary_context_recall"] == nil
    assert Map.has_key?(unlabelled_report["proxy_metrics"], "critical_context_shed")
  end
end
