defmodule Mix.Tasks.Conveyor.RunSlice do
  @moduledoc """
  Runs one Conveyor RunAttempt through its station plan.

      mix conveyor.run_slice RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]
  """

  use Mix.Task

  alias Conveyor.Artifacts.Projector
  alias Conveyor.CLI.ExitCodes
  alias Conveyor.RunSlice

  @shortdoc "Run a RunAttempt station plan"

  @impl Mix.Task
  def run([run_attempt_id | args]) do
    Mix.Task.run("app.start")
    opts = parse_opts!(args)

    result =
      RunSlice.run!(run_attempt_id,
        station_modules: station_modules(),
        actor: "run_slice",
        blob_root: Keyword.get(opts, :blob_root, ".conveyor/blobs")
      )

    projection =
      Projector.project_run!(
        result.run_attempt,
        Keyword.take(opts, [:blob_root, :projection_root])
      )

    %{
      "status" => Atom.to_string(result.status),
      "run_attempt_id" => result.run_attempt.id,
      "station_count" => length(result.station_runs),
      "projection_path" => projection.projection_path,
      "bundle_root_sha256" => projection.bundle_root_sha256
    }
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(exit_code(result.status))
  end

  def run(_args), do: Mix.raise(usage())

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args, strict: [blob_root: :string, projection_root: :string])

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    opts
  end

  defp station_modules do
    Process.get(:conveyor_run_slice_station_modules) ||
      Application.get_env(:conveyor, :station_modules, %{})
  end

  defp exit_code(:succeeded), do: ExitCodes.fetch!(:success)
  defp exit_code(:failed), do: ExitCodes.fetch!(:deterministic_gate_failed)

  defp usage do
    "usage: mix conveyor.run_slice RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]"
  end

  defp exit_fun do
    Process.get(:conveyor_run_slice_exit_fun, &System.halt/1)
  end
end
