defmodule Conveyor.Recovery.HonestyEval do
  @moduledoc """
  Labeled diagnosis/recovery honesty metrics.

  The evaluator is deliberately data-only: callers supply frozen case outcomes,
  and the report computes precision-oriented metrics without reclassifying the
  cases or authorizing recovery actions.
  """

  @schema_version "conveyor.diagnosis_recovery_honesty_eval@1"

  @spec evaluate([map()]) :: map()
  def evaluate(cases) when is_list(cases) do
    %{
      "schema_version" => @schema_version,
      "case_count" => length(cases),
      "coverage" => coverage(cases),
      "abstention_rate" => rate(count(cases, &abstained?/1), length(cases)),
      "abstention_appropriateness" => abstention_appropriateness(cases),
      "harmful_action_rate" => boolean_rate(cases, :harmful_action, true),
      "recovery_success_rate" => boolean_rate(cases, :recovery_succeeded, true),
      "idempotency_rate" => boolean_rate(cases, :idempotent, true),
      "effect_reconciliation_correctness" => reconciliation_correctness(cases),
      "invalidation_prediction_accuracy" => invalidation_prediction_accuracy(cases),
      "per_class" => per_class(cases)
    }
  end

  defp coverage(cases) do
    covered = count(cases, &(not abstained?(&1)))

    rate(covered, length(cases))
  end

  defp abstention_appropriateness(cases) do
    abstentions = Enum.filter(cases, &abstained?/1)

    case length(abstentions) do
      0 -> nil
      total -> rate(count(abstentions, &appropriate_abstention?/1), total)
    end
  end

  defp appropriate_abstention?(case_result) do
    value(case_result, :ambiguity_trap) == true ||
      value(case_result, :expected_classification) == "unknown"
  end

  defp boolean_rate(cases, key, expected_value) do
    labeled = Enum.filter(cases, &(not is_nil(value(&1, key))))

    case length(labeled) do
      0 -> nil
      total -> rate(count(labeled, &(value(&1, key) == expected_value)), total)
    end
  end

  defp reconciliation_correctness(cases) do
    labeled =
      Enum.filter(cases, fn case_result ->
        present?(value(case_result, :expected_reconciliation)) &&
          present?(value(case_result, :actual_reconciliation))
      end)

    case length(labeled) do
      0 ->
        nil

      total ->
        rate(
          count(labeled, fn case_result ->
            value(case_result, :expected_reconciliation) ==
              value(case_result, :actual_reconciliation)
          end),
          total
        )
    end
  end

  defp invalidation_prediction_accuracy(cases) do
    labeled =
      Enum.filter(cases, fn case_result ->
        is_list(value(case_result, :expected_invalidated_refs)) &&
          is_list(value(case_result, :predicted_invalidated_refs))
      end)

    case length(labeled) do
      0 ->
        nil

      total ->
        rate(
          count(labeled, fn case_result ->
            sorted(value(case_result, :expected_invalidated_refs)) ==
              sorted(value(case_result, :predicted_invalidated_refs))
          end),
          total
        )
    end
  end

  defp per_class(cases) do
    cases
    |> diagnosis_classes()
    |> Map.new(fn class ->
      true_positive =
        count(cases, fn case_result ->
          not abstained?(case_result) &&
            value(case_result, :expected_classification) == class &&
            value(case_result, :predicted_classification) == class
        end)

      false_positive =
        count(cases, fn case_result ->
          not abstained?(case_result) &&
            value(case_result, :expected_classification) != class &&
            value(case_result, :predicted_classification) == class
        end)

      false_negative =
        count(cases, fn case_result ->
          value(case_result, :expected_classification) == class &&
            (abstained?(case_result) || value(case_result, :predicted_classification) != class)
        end)

      {class,
       %{
         "true_positive" => true_positive,
         "false_positive" => false_positive,
         "false_negative" => false_negative,
         "precision" => ratio_or_nil(true_positive, true_positive + false_positive),
         "recall" => ratio_or_nil(true_positive, true_positive + false_negative)
       }}
    end)
  end

  defp diagnosis_classes(cases) do
    cases
    |> Enum.flat_map(fn case_result ->
      [
        value(case_result, :expected_classification),
        value(case_result, :predicted_classification)
      ]
    end)
    |> Enum.reject(&(&1 in [nil, "unknown"]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp abstained?(case_result), do: value(case_result, :abstained) == true

  defp count(values, fun), do: Enum.count(values, fun)

  defp rate(_count, 0), do: nil
  defp rate(count, total), do: count / total

  defp ratio_or_nil(_numerator, 0), do: nil
  defp ratio_or_nil(numerator, denominator), do: numerator / denominator

  defp present?(value), do: value not in [nil, ""]

  defp sorted(values), do: values |> Enum.map(&to_string/1) |> Enum.sort()

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)

    Map.get(map, key, Map.get(map, string_key, default))
  end
end
