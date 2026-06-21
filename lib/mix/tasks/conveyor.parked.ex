defmodule Mix.Tasks.Conveyor.Parked do
  @moduledoc """
  Lists the human-triage queue — runs that passed their gate but abstained (the
  calibrated TrustScore was not confident), least-trusted first.

      mix conveyor.parked

  Emits machine-readable JSON (`conveyor.parked_queue@1`). This is the operator
  payoff of ADR-23: review only what the factory honestly flagged.
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.ParkedQueue

  @shortdoc "List abstained (needs-a-human) runs with their trust verdict"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    entries = ParkedQueue.abstained()

    %{
      "schema_version" => "conveyor.parked_queue@1",
      "count" => length(entries),
      "abstained" => Enum.map(entries, &row/1)
    }
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp row(entry) do
    %{
      "slice_id" => entry.slice_id,
      "slice_title" => entry.slice_title,
      "run_attempt_id" => entry.run_attempt_id,
      "attempt_no" => entry.attempt_no,
      "band" => entry.band,
      "score" => entry.score
    }
  end

  defp exit_fun do
    Process.get(:conveyor_parked_exit_fun, &System.halt/1)
  end
end
