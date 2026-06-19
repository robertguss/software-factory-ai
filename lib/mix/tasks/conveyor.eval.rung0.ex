defmodule Mix.Tasks.Conveyor.Eval.Rung0 do
  @shortdoc "Run the Rung-0 evals (E1/E7/E8) and write their scorecard metric inputs"

  @moduledoc """
  Runs the deterministic, $0-LLM Rung-0 evals and writes their
  `conveyor.eval_metric@1` inputs to `eval/scorecards/inputs/` for
  `mix conveyor.eval.scorecard`. DB-free; needs Python/pytest for E1.

      mix conveyor.eval.rung0

  Emits: `compiler_invariant_violations` (E7), `sentinel_evasion_rate` (E8),
  `false_pass_rate` + `mutant_catch_rate` (E1), plus `work_graph_schema_present`
  and `sentinel_probe_coverage`.
  """

  use Mix.Task

  alias Conveyor.CanonicalJson
  alias Conveyor.Eval.{CompilerProperties, MutantGauntlet, SentinelTournament}

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:jsv)
    {:ok, _} = Application.ensure_all_started(:yaml_elixir)

    e7 = CompilerProperties.emit!()
    e8 = SentinelTournament.emit!()
    e1 = MutantGauntlet.emit!()

    Mix.shell().info(
      CanonicalJson.encode(%{
        "compiler_invariant_violations" => e7["violations"],
        "sentinel_evasion_rate" => e8["evasion_rate"],
        "false_pass_rate" => e1["false_pass_rate"],
        "mutant_catch_rate" => e1["mutant_catch_rate"]
      })
    )
  end
end
