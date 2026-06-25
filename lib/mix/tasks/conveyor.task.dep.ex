defmodule Mix.Tasks.Conveyor.Task.Dep do
  @moduledoc """
  Add or remove an execution-hard dependency edge between two tasks (by stable key) in an epic.

  `--from` is the **dependent** task and `--to` is its **prerequisite**: `add --from X --to Y`
  makes X depend on Y, so Y runs before X. This matches `br`'s `dep add <issue> <depends-on>`
  convention and the natural reading of the command.

      # SLICE-002 depends on SLICE-001, so SLICE-001 runs first:
      mix conveyor.task.dep add --epic EPIC_ID --from SLICE-002 --to SLICE-001
      mix conveyor.task.dep remove --epic EPIC_ID --from SLICE-002 --to SLICE-001
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "Add/remove a task dependency edge"

  @switches [epic: :string, from: :string, to: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, rest, _invalid} = OptionParser.parse(argv, strict: @switches)
    subcommand = List.first(rest)
    epic = opts[:epic] || Mix.raise(usage())
    from = opts[:from] || Mix.raise(usage())
    to = opts[:to] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      dependent = TaskGraph.task_by_stable_key!(epic, from)
      prerequisite = TaskGraph.task_by_stable_key!(epic, to)

      case subcommand do
        "add" ->
          # `--from` depends on `--to`: invert at the CLI boundary so the internal edge is
          # `prerequisite -> dependent` (meaning `dependent` depends on `prerequisite`).
          TaskGraph.add_dependency(prerequisite.id, dependent.id)
          TaskCommand.emit!(edge_payload(from, to, %{"kind" => "execution_hard"}))

        "remove" ->
          TaskGraph.remove_dependency(prerequisite.id, dependent.id)
          TaskCommand.emit!(edge_payload(from, to, %{"removed" => true}))

        _ ->
          Mix.raise(usage())
      end
    end)
  end

  # Spell out the orientation in the JSON so the relationship is unambiguous regardless of how the
  # reader interprets `from`/`to`: `from` is the dependent, `to` is the prerequisite.
  defp edge_payload(from, to, extra) do
    Map.merge(%{"from" => from, "to" => to, "dependent" => from, "prerequisite" => to}, extra)
  end

  defp usage,
    do: "usage: mix conveyor.task.dep add|remove --epic EPIC_ID --from KEY --to KEY"
end
