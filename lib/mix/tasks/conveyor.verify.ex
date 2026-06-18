defmodule Mix.Tasks.Conveyor.Verify do
  @moduledoc """
  Independently re-verifies a RunAttempt's artifact projection.

      mix conveyor.verify RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Replay

  @shortdoc "Re-project and verify a RunAttempt artifact bundle"

  @impl Mix.Task
  def run([run_attempt_id | args]) do
    Mix.Task.run("app.start")
    opts = parse_opts!(args)
    projection = Replay.project_run!(run_attempt_id, opts)

    projection
    |> Replay.format_project_result()
    |> Map.put("status", "verified")
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
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

  defp usage do
    "usage: mix conveyor.verify RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]"
  end

  defp exit_fun do
    Process.get(:conveyor_verify_exit_fun, &System.halt/1)
  end
end
