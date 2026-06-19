defmodule Conveyor.StationWorker.ExecuteStation do
  @moduledoc """
  Generic ExecuteStation worker skeleton.
  """

  alias Conveyor.StationWorker.Result

  @spec from_result!(map(), map()) :: Result.t()
  def from_result!(input, station_result) when is_map(input) and is_map(station_result) do
    %Result{
      input: input,
      output: Map.get(station_result, :output, Map.get(station_result, "output", %{})),
      diagnostics:
        Map.get(station_result, :diagnostics, Map.get(station_result, "diagnostics", [])),
      cache: Map.get(station_result, :cache, Map.get(station_result, "cache", %{})),
      trace_context:
        Map.get(station_result, :trace_context, Map.get(station_result, "trace_context", %{}))
    }
  end
end
