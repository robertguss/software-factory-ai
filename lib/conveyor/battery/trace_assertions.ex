defmodule Conveyor.Battery.TraceAssertions do
  @moduledoc """
  Evaluates Battery trace assertions against canonical events and effect receipts.
  """

  @spec evaluate([map()], map()) :: [map()]
  def evaluate(assertions, trace) when is_list(assertions) and is_map(trace) do
    Enum.map(assertions, &evaluate_one(&1, trace))
  end

  defp evaluate_one(%{} = assertion, trace) do
    records = source_records(trace, Map.fetch!(assertion, "source"))
    matches = Enum.filter(records, &matches?(&1, Map.fetch!(assertion, "match")))
    operator = Map.fetch!(assertion, "operator")

    result =
      case {operator, matches} do
        {"never", []} -> :passed
        {"never", _} -> :failed
        {"eventually", []} -> :failed
        {"eventually", _} -> :passed
        {"always", matches} when length(matches) == length(records) -> :passed
        {"always", _matches} -> :failed
        {"bounded_count", matches} -> bounded_count_result(assertion, length(matches))
      end

    %{
      assertion_id: Map.fetch!(assertion, "assertion_id"),
      result: result,
      observed_count: length(matches),
      matching_record_ids: Enum.map(matches, &record_id/1),
      failure_reason: failure_reason(operator, result)
    }
  end

  defp source_records(trace, "event"),
    do: Map.get(trace, :events) || Map.get(trace, "events") || []

  defp source_records(trace, "effect_receipt"),
    do: Map.get(trace, :effect_receipts) || Map.get(trace, "effect_receipts") || []

  defp matches?(record, %{"field" => field, "equals" => expected}) do
    get_field(record, field) == expected
  end

  defp get_field(record, field) do
    record
    |> normalize_record()
    |> get_in(String.split(field, "."))
  end

  defp normalize_record(record) when is_map(record) do
    Map.new(record, fn {key, value} -> {to_string(key), normalize_record(value)} end)
  end

  defp normalize_record(records) when is_list(records), do: Enum.map(records, &normalize_record/1)
  defp normalize_record(value), do: value

  defp record_id(record),
    do:
      Map.get(record, "event_id") ||
        Map.get(record, :event_id) ||
        Map.get(record, "idempotency_key") ||
        Map.get(record, :idempotency_key)

  defp failure_reason("never", :failed), do: :forbidden_match_observed
  defp failure_reason("eventually", :failed), do: :required_match_missing
  defp failure_reason("always", :failed), do: :not_all_records_matched
  defp failure_reason("bounded_count", :failed), do: :count_out_of_bounds
  defp failure_reason(_operator, :passed), do: nil

  defp bounded_count_result(assertion, count) do
    min_count = Map.get(assertion, "min_count", 0)
    max_count = Map.get(assertion, "max_count", :infinity)

    cond do
      count < min_count -> :failed
      max_count != :infinity and count > max_count -> :failed
      true -> :passed
    end
  end
end
