defmodule Mix.Tasks.Conveyor.Eval.Replay do
  @shortdoc "Replay the sealed cassette corpus and emit replay_fidelity"

  @moduledoc """
  Replays every sealed cassette under `eval/cassettes/` (DB-free, $0) and checks
  each synthesizes a `RawRunResult` whose digest matches the recorded one, then
  writes the `replay_fidelity` metric (target 1, blocking) for the scorecard.

      mix conveyor.eval.replay [--all]

  Cassettes are recorded by the eval tests (e.g. the cassette flywheel test), so run
  this after `mix test`. With an empty corpus it degrades to `replay_fidelity: 1.0`.
  """

  use Mix.Task

  alias Conveyor.CanonicalJson
  alias Conveyor.Eval.{CassetteBridge, Scorecard}

  @impl Mix.Task
  def run(_args) do
    report = CassetteBridge.replay_corpus()

    Scorecard.write_input!("cassette_flywheel", [
      Scorecard.metric("replay_fidelity", "cassette_flywheel", report.fidelity, 1,
        blocking: true,
        detail: "#{report.matched}/#{report.total} cassettes replay to the recorded digest"
      )
    ])

    Mix.shell().info(
      CanonicalJson.encode(%{
        "replay_fidelity" => report.fidelity,
        "matched" => report.matched,
        "total" => report.total
      })
    )
  end
end
