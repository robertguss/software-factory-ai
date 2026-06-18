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

  def run(_args) do
    Mix.raise("usage: mix conveyor.replay")
  end

  defp print_timeline(""), do: :ok
  defp print_timeline(output), do: Mix.shell().info(output)
end
