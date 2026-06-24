defmodule Mix.Tasks.Conveyor.RunView do
  @moduledoc """
  Show a finished or failed run's story, folded from its ledger stream.

      mix conveyor.run_view RUN_ID [--json]

  Prints a human-readable run story by default: the run's status, each slice's
  outcome, the slice the run stopped on, the failing gate stage and trust verdict,
  rework attempts, and token spend. `--json` emits the machine-readable
  `conveyor.run_view@1` envelope instead.

  Read-only: it folds the ledger and Factory resources and never writes or repairs
  them. An unknown run id prints an empty (`unknown`) story and still exits success
  — the report ran; the run's own outcome is data in the output, not the exit code.
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.RunReadModel

  @shortdoc "Show a run's per-slice story (read-after)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {run_id, json?} = parse_args!(args)

    run_id
    |> RunReadModel.summarize()
    |> render(json?)
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp parse_args!(args) do
    case OptionParser.parse(args, strict: [json: :boolean]) do
      {opts, [run_id], []} -> {run_id, Keyword.get(opts, :json, false)}
      _ -> Mix.raise(usage())
    end
  end

  defp render(story, true), do: story |> envelope() |> Jason.encode!()
  defp render(story, false), do: human(story)

  # --- JSON (conveyor.run_view@1) -------------------------------------------

  defp envelope(story) do
    %{
      "schema_version" => "conveyor.run_view@1",
      "run_id" => story.run_id,
      "status" => Atom.to_string(story.status),
      "stop_point" => story.stop_point,
      "slice_count" => story.slice_count,
      "slices" => Enum.map(story.slices, &slice_envelope/1)
    }
  end

  defp slice_envelope(slice) do
    %{
      "slice_id" => slice.slice_id,
      "sequence" => slice.sequence,
      "outcome" => slice.outcome,
      "run_attempt_outcome" => slice.run_attempt_outcome,
      "gate_result" => slice.gate_result,
      "findings" => slice.findings,
      "gate" => %{
        "failed_stage" => slice.gate.failed_stage,
        "failed_status" => slice.gate.failed_status,
        "verdict" => slice.gate.verdict
      },
      "rework_attempts" => slice.rework_attempts,
      "spend" => spend_envelope(slice.spend)
    }
  end

  defp spend_envelope(:unknown), do: "unknown"

  defp spend_envelope(%{tokens: tokens, cost_estimate: cost}) do
    %{"tokens" => tokens, "cost_estimate" => cost && Decimal.to_string(cost)}
  end

  # --- Human ----------------------------------------------------------------

  defp human(story) do
    header =
      "Run #{story.run_id}  [#{story.status}]  #{story.slice_count} slice(s)" <>
        stop_suffix(story.stop_point)

    [header | Enum.map(story.slices, &slice_line/1)] |> Enum.join("\n")
  end

  defp stop_suffix(nil), do: ""
  defp stop_suffix(slice_id), do: "  — stopped at #{slice_id}"

  defp slice_line(slice) do
    fields =
      [
        seq(slice.sequence),
        slice.slice_id,
        slice.outcome || "(no outcome)",
        gate_field(slice.gate),
        findings_field(slice.findings),
        verdict_field(slice.gate.verdict),
        rework_field(slice.rework_attempts),
        spend_field(slice.spend)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("  ")

    "  " <> fields
  end

  # The finding categories from the slice's committed outcome (e.g.
  # "out_of_scope_path") — the run-scoped reason a slice parked, even when the
  # DB gate stage cannot be resolved.
  defp findings_field([]), do: ""
  defp findings_field(findings), do: "findings:" <> Enum.join(findings, ",")

  defp seq(nil), do: "·"
  defp seq(n), do: "#{n}."

  defp gate_field(%{failed_stage: nil}), do: ""
  defp gate_field(%{failed_stage: stage, failed_status: status}), do: "gate:#{stage}=#{status}"

  defp verdict_field(nil), do: ""
  defp verdict_field(verdict) when map_size(verdict) == 0, do: ""

  defp verdict_field(verdict) do
    "verdict:" <>
      to_string(Map.get(verdict, "band", "?")) <> score_suffix(Map.get(verdict, "score"))
  end

  defp score_suffix(nil), do: ""
  defp score_suffix(score), do: "(#{score})"

  defp rework_field(n) when n > 1, do: "rework:#{n}"
  defp rework_field(_n), do: ""

  defp spend_field(:unknown), do: "spend:unknown"
  defp spend_field(%{tokens: tokens}), do: "spend:#{tokens}tok"

  defp usage, do: "usage: mix conveyor.run_view RUN_ID [--json]"

  defp exit_fun, do: Process.get(:conveyor_run_view_exit_fun, &System.halt/1)
end
