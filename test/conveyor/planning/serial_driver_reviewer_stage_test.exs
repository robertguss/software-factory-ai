defmodule Conveyor.Planning.SerialDriverReviewerStageTest do
  @moduledoc """
  m4b2.4 (foundation): the reviewer_aggregation stage joins the live gate stage list only when
  enabled, so hermetic/$0 paths stay at the 7 M4 stages. The full live wiring (trust integration +
  run_view + default-ON rollout) is the remaining scope; this pins the config-gated inclusion.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Gate.Stages.ReviewerAggregation
  alias Conveyor.Planning.SerialDriver

  test "default (disabled) keeps the 7 M4 stages — reviewer_aggregation is NOT required" do
    stages = SerialDriver.gate_stages([])
    refute ReviewerAggregation in stages
    assert length(stages) == 7
  end

  test "the per-run opt appends reviewer_aggregation as the 8th stage" do
    stages = SerialDriver.gate_stages(reviewer_aggregation: true)
    assert ReviewerAggregation in stages
    assert length(stages) == 8
    # it runs LAST — after the deterministic stages establish the diff is well-formed
    assert List.last(stages) == ReviewerAggregation
  end

  test "an explicit false opt overrides any config-on default" do
    refute ReviewerAggregation in SerialDriver.gate_stages(reviewer_aggregation: false)
  end
end
