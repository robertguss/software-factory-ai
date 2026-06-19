defmodule Mix.Tasks.Conveyor.Eval.Lift do
  @shortdoc "Project the lift-duel report(s) into scorecard metric inputs"

  @moduledoc """
  Reads the full `conveyor.eval_lift@1` report(s) under `eval/lift/` and writes their
  `lift_vs_vanilla` / `pass_at_1` / `cost_per_verified_ac` metrics to
  `eval/scorecards/inputs/` for `mix conveyor.eval.scorecard`. DB-free.

      mix conveyor.eval.lift

  The reports are produced by the R5 lift-duel eval during `mix test` (the duel needs
  the DB-backed agent-session chain, so it runs as a test — like the Golden Thread),
  or, once a cassette corpus exists, by replaying it (B4). This task is the DB-free
  measurement→reporting seam: with no report present it degrades gracefully (emits
  nothing), mirroring `mix conveyor.eval.replay` on an empty corpus.
  """

  use Mix.Task

  alias Conveyor.CanonicalJson
  alias Conveyor.Eval.{LiftDuel, Scorecard}

  @impl Mix.Task
  def run(_args) do
    case LiftDuel.load_reports() do
      [] ->
        Mix.shell().info(
          "no lift reports under #{LiftDuel.reports_dir()}/ — run the lift-duel eval first"
        )

      reports ->
        Enum.each(reports, &project/1)
    end
  end

  defp project({name, report}) do
    Scorecard.write_input!(name, LiftDuel.metrics(report))
    Mix.shell().info(CanonicalJson.encode(summary(name, report)))
  end

  defp summary(name, report) do
    lift = report["lift"]

    %{
      "report" => name,
      "reasoning_effort" => report["reasoning_effort"],
      "treatment_arm" => lift["treatment_arm"],
      "lift_vs_vanilla" => lift["pass_at_1_delta"],
      "verified_acs_delta" => lift["verified_acs_delta"]
    }
  end
end
