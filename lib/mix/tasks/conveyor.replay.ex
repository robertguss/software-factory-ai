defmodule Mix.Tasks.Conveyor.Replay do
  @moduledoc """
  Rebuilds the R0 human timeline from LedgerEvent records.

      mix conveyor.replay
  """

  use Mix.Task

  alias Conveyor.Replay

  @shortdoc "Replay the R0 ledger timeline"

  @impl Mix.Task
  def run([]) do
    Mix.Task.run("app.start")

    Replay.timeline!()
    |> Replay.format_timeline()
    |> print_timeline()
  end

  def run([run_attempt_id | args]) do
    Mix.Task.run("app.start")

    opts = parse_r1_opts!(args)

    run_attempt_id
    |> Replay.project_run!(opts)
    |> Replay.format_project_result()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  def run(_args) do
    Mix.raise(usage())
  end

  defp print_timeline(""), do: :ok
  defp print_timeline(output), do: Mix.shell().info(output)

  defp parse_r1_opts!(args) do
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
      mix conveyor.replay
      mix conveyor.replay RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]
    """
    |> String.trim()
  end
end
