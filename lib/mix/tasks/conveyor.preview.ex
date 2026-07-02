defmodule Mix.Tasks.Conveyor.Preview do
  @moduledoc """
  Dry-run preview of a plan (a3hf.2.2.3): renders the computed work graph, each slice's
  contract summary, the plan-lint warnings, and a cost estimate — behind the approve-to-run
  gate, so nothing is spent until `mix conveyor.plan.approve PLAN_ID` is run.

      mix conveyor.preview PLAN_ID [--format text|json]
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Planning.Preview

  @shortdoc "Dry-run preview of a plan before approving it"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, rest, _invalid} = OptionParser.parse(argv, strict: [format: :string])

    case rest do
      [plan_id] -> emit(Preview.assemble(plan_id), opts[:format] || "text")
      _ -> Mix.raise("usage: mix conveyor.preview PLAN_ID [--format text|json]")
    end
  end

  defp emit(preview, "json") do
    IO.puts(Jason.encode!(preview))
    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp emit(preview, _text) do
    IO.puts(render_text(preview))
    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp render_text(preview) do
    [
      "Plan #{preview.plan_id} (#{preview.status})",
      "",
      "Slices (#{length(preview.slices)}):",
      Enum.map_join(preview.slices, "\n", fn s ->
        "  #{s["stable_key"]} — #{s["title"]} (files: #{length(s["likely_files"])})"
      end),
      "",
      "Dependencies: #{length(preview.dependencies)}",
      "",
      "Lint warnings (#{length(preview.warnings)}):",
      warnings_text(preview.warnings),
      "",
      "Cost estimate: #{estimate_text(preview.estimate)}",
      "",
      approve_note(preview)
    ]
    |> Enum.join("\n")
  end

  defp warnings_text([]), do: "  (none)"

  defp warnings_text(warnings),
    do:
      Enum.map_join(warnings, "\n", fn w -> "  [#{w.rule_key}] #{w.subject_key}: #{w.message}" end)

  defp estimate_text(%{basis: "none", reason: reason}), do: "no basis (#{reason})"

  defp estimate_text(%{basis: "historical", tokens: tokens}),
    do: "~#{tokens.expected} tokens (range #{tokens.low}–#{tokens.high})"

  defp approve_note(%{approved?: true}), do: "This plan is approved and ready to run."

  defp approve_note(%{plan_id: plan_id}),
    do: "Run is blocked until approved: mix conveyor.plan.approve #{plan_id}"

  defp exit_fun, do: Process.get(:conveyor_preview_exit_fun, &System.halt/1)
end
