defmodule Mix.Tasks.Conveyor.Show do
  @moduledoc """
  Shows a compact machine-readable Slice status.

      mix conveyor.show SLICE_ID
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun

  @shortdoc "Show Slice and latest RunAttempt status"

  @impl Mix.Task
  def run([slice_id]) do
    Mix.Task.run("app.start")
    slice = get_by_id!(Slice, slice_id)
    run_attempt = latest_run_attempt(slice.id)
    station_runs = station_runs(run_attempt)

    %{
      "slice_id" => slice.id,
      "title" => slice.title,
      "state" => Atom.to_string(slice.state),
      "latest_run_attempt_id" => run_attempt && run_attempt.id,
      "latest_run_attempt_status" => run_attempt && Atom.to_string(run_attempt.status),
      "latest_run_attempt_outcome" => run_attempt && Atom.to_string(run_attempt.outcome),
      "trust_verdict" => trust_verdict(run_attempt),
      "station_runs" => Enum.map(station_runs, & &1.station)
    }
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  def run(_args), do: Mix.raise(usage())

  defp latest_run_attempt(slice_id) do
    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(& &1.attempt_no, :desc)
    |> List.first()
  end

  # ADR-23: the calibrated trust verdict from the latest gate result, so an
  # operator can see *why* a slice abstained/parked.
  defp trust_verdict(nil), do: nil

  defp trust_verdict(run_attempt) do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id and &1.trust_score))
    |> List.last()
    |> case do
      nil -> nil
      gate_result -> Map.take(gate_result.trust_score, ["band", "score"])
    end
  end

  defp station_runs(nil), do: []

  defp station_runs(run_attempt) do
    StationRun
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
    |> Enum.sort_by(& &1.station)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp usage do
    "usage: mix conveyor.show SLICE_ID"
  end

  defp exit_fun do
    Process.get(:conveyor_show_exit_fun, &System.halt/1)
  end
end
