defmodule Conveyor.Cassettes.ReplayDiagnostics do
  @moduledoc """
  Structured diagnostics for strict replay divergence.
  """

  @spec compare(map(), map()) :: [map()]
  def compare(recorded, requested) when is_map(recorded) and is_map(requested) do
    cond do
      causal_signature(recorded) != causal_signature(requested) ->
        [finding("strict_replay.causal_sequence_changed", "causal_events")]

      tool_contracts(recorded) != tool_contracts(requested) ->
        [finding("strict_replay.tool_contract_changed", first_tool_anchor(recorded, requested))]

      tool_args(recorded) != tool_args(requested) ->
        [finding("strict_replay.normalized_args_changed", first_tool_anchor(recorded, requested))]

      true ->
        []
    end
  end

  defp finding(rule_key, anchor) do
    %{
      rule_key: rule_key,
      anchor: anchor,
      severity: :blocking,
      next_action: :record_new_cassette_or_fix_replay_request
    }
  end

  defp causal_signature(value) do
    value
    |> entries(:causal_events)
    |> Enum.map(&{Map.get(&1, "event_id"), Map.get(&1, "happens_after", [])})
  end

  defp tool_contracts(value) do
    value
    |> entries(:tool_records)
    |> Enum.map(&{Map.get(&1, "tool_call_id"), Map.get(&1, "tool_contract_key")})
  end

  defp tool_args(value) do
    value
    |> entries(:tool_records)
    |> Enum.map(&{Map.get(&1, "tool_call_id"), canonical(Map.get(&1, "normalized_args", %{}))})
  end

  defp first_tool_anchor(recorded, requested) do
    recorded_anchor = recorded |> entries(:tool_records) |> List.first() |> tool_anchor()
    requested_anchor = requested |> entries(:tool_records) |> List.first() |> tool_anchor()
    recorded_anchor || requested_anchor || "tool_records"
  end

  defp tool_anchor(nil), do: nil
  defp tool_anchor(record), do: Map.get(record, "tool_call_id") || "tool_records"

  defp entries(value, key), do: Map.get(value, key) || Map.get(value, Atom.to_string(key)) || []

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value
end
