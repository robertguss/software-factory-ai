defmodule Conveyor.BatteryMeasurementStudyTest do
  use ExUnit.Case, async: true

  alias Conveyor.Battery.MeasurementStudy

  test "records Scout AGENTS prompt and adapter ablations against frozen inputs" do
    report =
      MeasurementStudy.run!(%{
        study_id: "study:phase-1.5-ablation",
        frozen_input_digest: "sha256:#{String.duplicate("a", 64)}",
        variants: [
          %{variant_id: "scout-on", dimension: "scout", outcome: "positive", metric_delta: 0.12},
          %{
            variant_id: "agents-md-v2",
            dimension: "agents_md",
            outcome: "negative",
            metric_delta: -0.08
          },
          %{variant_id: "prompt-v3", dimension: "prompt", outcome: nil, metric_delta: nil},
          %{variant_id: "adapter-b", dimension: "adapter", outcome: "neutral", metric_delta: 0.0}
        ]
      })

    assert report["schema_version"] == "conveyor.measurement_study@1"
    assert report["study_id"] == "study:phase-1.5-ablation"
    assert report["frozen_input_digest"] == "sha256:#{String.duplicate("a", 64)}"
    assert report["covered_dimensions"] == ["adapter", "agents_md", "prompt", "scout"]
    assert report["negative_result_count"] == 1
    assert report["null_result_count"] == 1

    assert Enum.map(report["results"], & &1["retention"]) == [
             "retained",
             "retained",
             "retained",
             "retained"
           ]

    assert Enum.find(report["results"], &(&1["variant_id"] == "agents-md-v2"))["outcome"] ==
             "negative"

    assert Enum.find(report["results"], &(&1["variant_id"] == "prompt-v3"))["outcome"] ==
             nil
  end

  test "rejects studies without a frozen input digest" do
    assert_raise ArgumentError, ~r/frozen_input_digest is required/, fn ->
      MeasurementStudy.run!(%{study_id: "study:missing-freeze", variants: []})
    end
  end
end
