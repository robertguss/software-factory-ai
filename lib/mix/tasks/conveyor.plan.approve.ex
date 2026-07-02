defmodule Mix.Tasks.Conveyor.Plan.Approve do
  @moduledoc """
  Bulk lock + approve every drafted slice of a plan behind a plan-lint gate (aaun.1).

  Prints a compact per-slice summary to stderr, asks one confirmation (or `--yes`),
  then locks and approves the still-drafted slices in dependency order. A lint-failing
  plan is refused with the findings as JSON on stdout and a non-zero exit — bulk-approve
  never becomes bulk-rubber-stamp.

      mix conveyor.plan.approve PLAN_ID [--yes]
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Planning.PlanApprove

  @shortdoc "Bulk lock + approve a plan's slices behind a plan-lint gate"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, rest, _invalid} = OptionParser.parse(argv, strict: [yes: :boolean])

    case rest do
      [plan_id] -> approve(plan_id, opts)
      _ -> Mix.raise("usage: mix conveyor.plan.approve PLAN_ID [--yes]")
    end
  end

  defp approve(plan_id, opts) do
    case PlanApprove.preview(plan_id) do
      {:blocked, lint} ->
        emit(%{"status" => "blocked", "findings" => findings(lint)})
        exit_fun().(ExitCodes.fetch!(:plan_or_readiness_blocked))

      {:ok, %{slices: slices}} ->
        print_summary(slices)

        if opts[:yes] || confirm?(slices) do
          {:ok, result} = PlanApprove.approve_all!(plan_id)

          emit(%{
            "status" => "approved",
            "approved" => result.approved,
            "already_approved" => result.already_approved
          })

          exit_fun().(ExitCodes.fetch!(:success))
        else
          IO.puts(:stderr, "aborted: no slices approved")
          exit_fun().(ExitCodes.fetch!(:success))
        end
    end
  end

  defp print_summary(slices) do
    IO.puts(:stderr, "#{length(slices)} slice(s):")

    Enum.each(slices, fn s ->
      IO.puts(
        :stderr,
        "  #{s["stable_key"]} [#{s["state"]}] #{s["title"]} " <>
          "(files: #{s["likely_files"]}, acceptance: #{s["acceptance_criteria"]})"
      )
    end)
  end

  defp confirm?(slices), do: Mix.shell().yes?("Lock + approve #{length(slices)} slice(s)?")

  defp findings(%{findings: findings}) do
    Enum.map(findings, fn f ->
      %{
        "rule_key" => f[:rule_key],
        "subject_key" => f[:subject_key],
        "message" => f[:message]
      }
    end)
  end

  defp emit(map), do: IO.puts(Jason.encode!(map))

  defp exit_fun, do: Process.get(:conveyor_plan_approve_exit_fun, &System.halt/1)
end
