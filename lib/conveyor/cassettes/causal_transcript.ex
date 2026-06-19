defmodule Conveyor.Cassettes.CausalTranscript do
  @moduledoc """
  Normalizes observable cassette event streams and tool records.
  """

  @hidden_keys MapSet.new([
                 "chain_of_thought",
                 "hidden_chain_of_thought",
                 "reasoning",
                 "private_reasoning"
               ])

  @spec normalize_events([map()]) :: [map()]
  def normalize_events(events) when is_list(events) do
    {_counters, normalized} =
      Enum.reduce(events, {%{}, []}, fn event, {counters, acc} ->
        stream = required_string(event, :stream)
        sequence_no = Map.get(counters, stream, 0) + 1

        normalized_event = %{
          "schema_version" => "conveyor.causal_event@1",
          "event_id" => "#{stream}:#{sequence_no}",
          "stream" => stream,
          "stream_sequence_no" => sequence_no,
          "event_type" => required_string(event, :event_type),
          "happens_after" => List.wrap(value(event, :happens_after)),
          "payload" => event |> value(:payload) |> scrub_hidden()
        }

        {Map.put(counters, stream, sequence_no), [normalized_event | acc]}
      end)

    Enum.reverse(normalized)
  end

  @spec tool_record!(map()) :: map()
  def tool_record!(attrs) when is_map(attrs) do
    record = %{
      "schema_version" => "conveyor.tool_record@1",
      "tool_contract_key" => required_string(attrs, :tool_contract_key),
      "tool_call_id" => required_string(attrs, :tool_call_id),
      "normalized_args" => attrs |> value(:normalized_args) |> scrub_hidden(),
      "policy_decision" => attrs |> value(:policy_decision) |> scrub_hidden(),
      "result" => attrs |> value(:result) |> scrub_hidden(),
      "error" => attrs |> value(:error) |> scrub_hidden(),
      "effect_receipt_ref" => value(attrs, :effect_receipt_ref),
      "caused_by" => required_string(attrs, :caused_by)
    }

    Map.put(record, "idempotency_key", idempotency_key(record))
  end

  defp idempotency_key(record) do
    record
    |> Map.delete("idempotency_key")
    |> digest()
    |> then(&"tool-record:#{&1}")
  end

  defp scrub_hidden(map) when is_map(map) do
    map
    |> Enum.reject(fn {key, _value} -> MapSet.member?(@hidden_keys, to_string(key)) end)
    |> Map.new(fn {key, value} -> {to_string(key), scrub_hidden(value)} end)
  end

  defp scrub_hidden(values) when is_list(values), do: Enum.map(values, &scrub_hidden/1)
  defp scrub_hidden(value), do: value

  defp digest(value) do
    value
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp required_string(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
