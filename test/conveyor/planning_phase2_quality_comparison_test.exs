defmodule Conveyor.PlanningPhase2QualityComparisonTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.Phase2QualityComparison

  @report_path "test/fixtures/phase-2/p2-b8/quality-hypothesis-comparison.md"
  @hypotheses [
    "approved_without_rewrite",
    "median_repair_rounds",
    "first_pass_gate_success",
    "material_dispute_rate",
    "critic_planted_loophole_catch",
    "lost_falsifier_or_obligation",
    "impact_preview_matches_actual"
  ]

  test "compares phase 2 quality hypotheses with observed pilot evidence" do
    comparison =
      Phase2QualityComparison.compare(%{
        approved_without_rewrite_rate: 1.0,
        median_repair_rounds: 1,
        first_pass_gate_success_rate: 1 / 3,
        material_dispute_rate: 1 / 3,
        critic_planted_loophole_catch_rate: 1.0,
        lost_falsifier_or_obligation_count: 0,
        impact_preview_match_rate: 1.0,
        phase_next_decision_changes: []
      })

    assert status(comparison, "approved_without_rewrite") == "met"
    assert status(comparison, "median_repair_rounds") == "met"
    assert status(comparison, "first_pass_gate_success") == "missed"
    assert status(comparison, "material_dispute_rate") == "missed"
    assert status(comparison, "critic_planted_loophole_catch") == "met"
    assert status(comparison, "lost_falsifier_or_obligation") == "met"
    assert status(comparison, "impact_preview_matches_actual") == "met"

    assert Phase2QualityComparison.summary(comparison) == %{
             "met" => 5,
             "missed" => 2,
             "superseded_by_phase_next_decision" => 0
           }
  end

  test "missed hypotheses remain misses until PhaseNextDecision changes them" do
    comparison =
      Phase2QualityComparison.compare(%{
        approved_without_rewrite_rate: 1.0,
        median_repair_rounds: 1,
        first_pass_gate_success_rate: 1 / 3,
        material_dispute_rate: 1 / 3,
        critic_planted_loophole_catch_rate: 1.0,
        lost_falsifier_or_obligation_count: 0,
        impact_preview_match_rate: 1.0,
        phase_next_decision_changes: ["first_pass_gate_success"]
      })

    assert status(comparison, "first_pass_gate_success") ==
             "superseded_by_phase_next_decision"

    assert status(comparison, "material_dispute_rate") == "missed"
  end

  test "published comparison records every initial hypothesis and miss state" do
    report = File.read!(@report_path)

    for hypothesis <- @hypotheses do
      assert report =~ hypothesis
    end

    assert report =~
             "Misses remain misses until a recorded PhaseNextDecision changes a hypothesis"

    assert report =~ "first_pass_gate_success"
    assert report =~ "material_dispute_rate"
    assert report =~ "missed"
    assert report =~ "met"
  end

  defp status(comparison, hypothesis) do
    comparison
    |> Enum.find(&(&1["hypothesis"] == hypothesis))
    |> Map.fetch!("status")
  end
end
