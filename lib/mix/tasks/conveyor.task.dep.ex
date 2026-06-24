defmodule Mix.Tasks.Conveyor.Task.Dep do
  @moduledoc """
  Add or remove an execution-hard dependency edge between two tasks (by stable key) in an epic.

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
      from_task = TaskGraph.task_by_stable_key!(epic, from)
      to_task = TaskGraph.task_by_stable_key!(epic, to)

      case subcommand do
        "add" ->
          TaskGraph.add_dependency(from_task.id, to_task.id)
          TaskCommand.emit!(%{"from" => from, "to" => to, "kind" => "execution_hard"})

        "remove" ->
          TaskGraph.remove_dependency(from_task.id, to_task.id)
          TaskCommand.emit!(%{"from" => from, "to" => to, "removed" => true})

        _ ->
          Mix.raise(usage())
      end
    end)
  end

  defp usage,
    do: "usage: mix conveyor.task.dep add|remove --epic EPIC_ID --from KEY --to KEY"
end
