defmodule Conveyor.Factory.StationPlan do
  @moduledoc """
  Validator for embedded `conveyor.station_plan@1` maps.
  """

  @schema_version "conveyor.station_plan@1"

  @doc """
  Validates a station plan against a RunSpec digest.
  """
  def validate(plan, run_spec_sha256) when is_map(plan) and is_binary(run_spec_sha256) do
    with :ok <- require_equal(plan, "schema_version", @schema_version),
         {:ok, stations} <- fetch_stations(plan),
         :ok <- validate_stations(stations, run_spec_sha256) do
      :ok
    end
  end

  def validate(_plan, _run_spec_sha256) do
    {:error, "station_plan must be a map and run_spec_sha256 must be present"}
  end

  defp fetch_stations(plan) do
    case get(plan, "stations") do
      stations when is_list(stations) and stations != [] -> {:ok, stations}
      _ -> {:error, "station_plan.stations must be a non-empty list"}
    end
  end

  defp validate_stations(stations, run_spec_sha256) do
    stations
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {station, index}, :ok ->
      case validate_station(station, run_spec_sha256) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "station #{index}: #{reason}"}}
      end
    end)
  end

  defp validate_station(station, run_spec_sha256) when is_map(station) do
    with key when is_binary(key) <- get(station, "key"),
         input when is_map(input) <- get(station, "input"),
         output when is_map(output) <- get(station, "output"),
         :ok <- require_equal(input, "run_spec_sha256", run_spec_sha256),
         :ok <- require_equal(output, "run_spec_sha256", run_spec_sha256) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "key, input, and output are required"}
    end
  end

  defp validate_station(_station, _run_spec_sha256), do: {:error, "station must be a map"}

  defp require_equal(map, key, expected) do
    case get(map, key) do
      ^expected -> :ok
      _ -> {:error, "#{key} must be #{expected}"}
    end
  end

  defp get(map, key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end
end
