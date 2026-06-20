defmodule Conveyor.Planning.WorkGraphToStationPlan do
  @moduledoc """
  Lowers a single-slice work graph into the production width-1 station plan.

  The lowering is pure: it depends only on the work graph and the immutable
  RunSpec digest. Runtime values such as workspace paths are added later by
  `Conveyor.Planning.RunSpecAssembler`.
  """

  alias Conveyor.CanonicalJson

  @stations [
    {"context_scout", "context", Conveyor.Stations.ContextScout},
    {"baseline_health", "verify", Conveyor.Stations.BaselineHealth},
    {"acceptance_calibration", "verify", Conveyor.Stations.AcceptanceCalibration},
    {"implement", "agent", Conveyor.Stations.Implementer},
    {"verify", "verify", Conveyor.Stations.Verify},
    {"record_evidence", "evidence", Conveyor.Stations.RecordEvidence}
  ]

  @doc """
  Lower a single-slice `work_graph@2` into a station plan bound to
  `run_spec_sha256`.
  """
  @spec lower(map(), String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def lower(work_graph, run_spec_sha256, _opts \\ []) do
    with {:ok, slice} <- single_slice(work_graph) do
      io = %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []}

      {:ok,
       %{
         "schema_version" => "conveyor.station_plan@1",
         "stations" => Enum.map(@stations, &station_def(&1, io)),
         "work_graph_digest" => CanonicalJson.digest(work_graph),
         "slice_stable_key" => fetch(slice, "stable_key")
       }}
    end
  end

  defp station_def({key, kind, module}, io) do
    %{
      "key" => key,
      "kind" => kind,
      "module" => inspect(module),
      "input" => io,
      "output" => io
    }
  end

  defp single_slice(work_graph) do
    case fetch(work_graph, "slices") do
      [slice] ->
        {:ok, slice}

      [_ | _] = slices ->
        {:error, %{reason: :multi_slice_unsupported, slice_count: length(slices)}}

      _ ->
        {:error, %{reason: :no_slices}}
    end
  end

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, String.to_atom(key))

  defp fetch(_map, _key), do: nil
end
