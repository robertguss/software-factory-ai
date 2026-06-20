defmodule Conveyor.Stations.AcceptanceCalibration do
  @moduledoc "Station wrapper for locked acceptance-test calibration."

  use Conveyor.Station, station: "acceptance_calibration"

  alias Conveyor.AcceptanceCalibration
  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec

  @impl Conveyor.Station
  def run(input, context) do
    calibration =
      context.run_attempt.run_spec_id
      |> run_spec!()
      |> AcceptanceCalibration.run!(blob_root: Map.get(input, "blob_root", ".conveyor/blobs"))

    {:ok,
     %{
       "test_pack_calibration" => %{
         "id" => calibration.id,
         "status" => Atom.to_string(calibration.status),
         "expected_failures" => calibration.expected_failures
       }
     }}
  end

  defp run_spec!(id) do
    RunSpec
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "RunSpec #{id} was not found"
  end
end
