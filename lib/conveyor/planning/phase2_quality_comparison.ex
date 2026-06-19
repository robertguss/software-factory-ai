defmodule Conveyor.Planning.Phase2QualityComparison do
  @moduledoc """
  Compares Phase 2 quality hypotheses with observed pilot evidence.
  """

  @hypotheses [
    {"approved_without_rewrite", ">= 80%", :approved_without_rewrite_rate, :gte, 0.8},
    {"median_repair_rounds", "<= 1", :median_repair_rounds, :lte, 1},
    {"first_pass_gate_success", ">= 70%", :first_pass_gate_success_rate, :gte, 0.7},
    {"material_dispute_rate", "< 20%", :material_dispute_rate, :lt, 0.2},
    {"critic_planted_loophole_catch", "100%", :critic_planted_loophole_catch_rate, :eq, 1.0},
    {"lost_falsifier_or_obligation", "0", :lost_falsifier_or_obligation_count, :eq, 0},
    {"impact_preview_matches_actual", "100%", :impact_preview_match_rate, :eq, 1.0}
  ]

  @spec compare(map()) :: [map()]
  def compare(observations) when is_map(observations) do
    changed =
      observations
      |> value(:phase_next_decision_changes, [])
      |> List.wrap()
      |> MapSet.new(&to_string/1)

    Enum.map(@hypotheses, fn {hypothesis, target, key, comparator, threshold} ->
      observed = value(observations, key)
      met? = meets?(observed, comparator, threshold)

      status =
        cond do
          met? -> "met"
          MapSet.member?(changed, hypothesis) -> "superseded_by_phase_next_decision"
          true -> "missed"
        end

      %{
        "hypothesis" => hypothesis,
        "target" => target,
        "observed" => observed,
        "status" => status
      }
    end)
  end

  @spec summary([map()]) :: map()
  def summary(comparison) when is_list(comparison) do
    counts = Enum.frequencies_by(comparison, &value(&1, :status))

    %{
      "met" => Map.get(counts, "met", 0),
      "missed" => Map.get(counts, "missed", 0),
      "superseded_by_phase_next_decision" =>
        Map.get(counts, "superseded_by_phase_next_decision", 0)
    }
  end

  defp meets?(observed, comparator, threshold) when is_number(observed) do
    case comparator do
      :gte -> observed >= threshold
      :lte -> observed <= threshold
      :lt -> observed < threshold
      :eq -> observed == threshold
    end
  end

  defp meets?(_observed, _comparator, _threshold), do: false

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))
end
