defmodule Mix.Tasks.Conveyor.Demo do
  @moduledoc """
  Runs the hermetic Conveyor tracer demo.

      mix conveyor.demo [--blob-root PATH] [--projection-root PATH]
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Demo

  @shortdoc "Run the hermetic Phase-1 Conveyor demo"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_opts!()
    |> Demo.run!()
    |> Demo.summary()
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [blob_root: :string, projection_root: :string]
      )

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    opts
  end

  defp usage do
    """
    usage:
      mix conveyor.demo [--blob-root PATH] [--projection-root PATH]
    """
    |> String.trim()
  end

  defp exit_fun do
    Process.get(:conveyor_demo_exit_fun, &System.halt/1)
  end
end
