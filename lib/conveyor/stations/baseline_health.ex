defmodule Conveyor.Stations.BaselineHealth do
  @moduledoc "Station wrapper for baseline regression health checks."

  use Conveyor.Station, station: "baseline_health"

  alias Conveyor.BaselineHealth
  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec

  @impl Conveyor.Station
  def run(_input, context) do
    result =
      context.run_attempt.run_spec_id
      |> run_spec!()
      |> BaselineHealth.run!()

    {:ok,
     %{
       "baseline_health_status" => Atom.to_string(result.status),
       "baseline_suites" => result.suites
     }}
  end

  defp run_spec!(id) do
    RunSpec
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "RunSpec #{id} was not found"
  end
end
