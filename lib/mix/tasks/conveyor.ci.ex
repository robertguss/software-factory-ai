defmodule Mix.Tasks.Conveyor.Ci do
  @moduledoc """
  Runs Conveyor's hermetic CI smoke path.

      mix conveyor.ci [--blob-root PATH] [--projection-root PATH]
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Demo

  @shortdoc "Run Conveyor headless CI smoke path"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_opts!()
    |> Demo.run!()
    |> Demo.summary()
    |> Map.put("mode", "ci")
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args, strict: [blob_root: :string, projection_root: :string])

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    opts
  end

  defp usage do
    "usage: mix conveyor.ci [--blob-root PATH] [--projection-root PATH]"
  end

  defp exit_fun do
    Process.get(:conveyor_ci_exit_fun, &System.halt/1)
  end
end
