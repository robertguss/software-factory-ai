defmodule Conveyor.Planning.PilotExecution do
  @moduledoc """
  Summarizes serial execution of a pre-registered pilot selection.
  """

  @spec summarize(map()) :: map()
  def summarize(input) when is_map(input) do
    if value(input, :implementation_width) != 1 do
      %{
        "status" => "blocked",
        "blocking_reasons" => ["implementation_width_not_one"]
      }
    else
      events = input |> list(:events) |> Enum.sort_by(&value(&1, :sequence))
      selected_count = max(length(list(input, :selected_slice_ids)), 1)

      %{
        "status" => "serial_execution_recorded",
        "implementation_width" => 1,
        "serial_order" => Enum.map(events, &value(&1, :slice_id)),
        "first_pass_gate_success_rate" => count_gate(events, "first_pass") / selected_count,
        "eventual_gate_success_rate" => count_eventual_success(events) / selected_count,
        "clarification_or_dispute_rate" =>
          count_clarification_or_dispute(events) / selected_count,
        "passed_count" => count_status(events, "passed"),
        "parked_count" => count_status(events, "parked"),
        "skipped_count" => count_status(events, "skipped"),
        "context_miss_count" => count_finding(events, "context_miss"),
        "missing_obligation_or_interface_count" =>
          count_any_finding(events, ["missing_obligation", "missing_interface"]),
        "post_start_amendment_count" => count_finding(events, "post_start_amendment"),
        "human_edit_count" => count_finding(events, "human_edit"),
        "incident_counts" => incident_counts(input),
        "diagnosis_recovery_quality" => diagnosis_recovery_quality(input)
      }
    end
  end

  defp count_gate(events, gate_result),
    do: Enum.count(events, &(value(&1, :gate_result) == gate_result))

  defp count_status(events, status),
    do: Enum.count(events, &(value(&1, :status) == status))

  defp count_eventual_success(events) do
    Enum.count(events, &(value(&1, :gate_result) in ["first_pass", "recovered"]))
  end

  defp count_clarification_or_dispute(events) do
    Enum.count(events, fn event ->
      value(event, :status) in ["parked", "disputed"] or
        Enum.any?(strings(event, :findings), &(&1 in ["clarification", "dispute"]))
    end)
  end

  defp count_finding(events, finding),
    do: Enum.count(events, &(finding in strings(&1, :findings)))

  defp count_any_finding(events, findings) do
    Enum.count(events, fn event ->
      Enum.any?(strings(event, :findings), &(&1 in findings))
    end)
  end

  defp incident_counts(input) do
    input
    |> list(:incidents)
    |> Enum.frequencies_by(&value(&1, :kind))
    |> Map.new(fn {kind, count} -> {to_string(kind), count} end)
  end

  defp diagnosis_recovery_quality(input) do
    records = list(input, :diagnosis_records) ++ list(input, :recovery_records)

    if records != [] and Enum.all?(records, &(value(&1, :quality) == "complete")) do
      "complete"
    else
      "incomplete"
    end
  end

  defp strings(map, key) do
    map
    |> value(key, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))
end
