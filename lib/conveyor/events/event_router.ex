defmodule Conveyor.Events.EventRouter do
  @moduledoc """
  Assigns deterministic routing metadata to authority/progress events.
  """

  @spec route([map()], keyword()) :: [map()]
  def route(events, opts \\ []) when is_list(events) do
    correlation_id = Keyword.get_lazy(opts, :correlation_id, fn -> random_id("corr") end)
    trace_id = Keyword.get(opts, :trace_id, correlation_id)
    start_sequence = Keyword.get(opts, :start_sequence, 1)

    events
    |> Enum.with_index(start_sequence)
    |> Enum.map_reduce(nil, fn {event, sequence}, previous_event_id ->
      event_id = Map.get(event, "event_id") || Map.get(event, :event_id) || random_id("evt")

      routed =
        event
        |> stringify_keys()
        |> Map.put("event_id", event_id)
        |> Map.put("sequence", sequence)
        |> Map.put_new("causation_id", previous_event_id)
        |> Map.put("correlation_id", correlation_id)
        |> Map.put("trace_context", %{"trace_id" => trace_id})

      {routed, event_id}
    end)
    |> elem(0)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp random_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
