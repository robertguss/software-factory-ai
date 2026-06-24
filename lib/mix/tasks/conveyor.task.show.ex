defmodule Mix.Tasks.Conveyor.Task.Show do
  @moduledoc """
  Show one task (by stable key within an epic) as JSON.

      mix conveyor.task.show --epic EPIC_ID --key SLICE-001
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "Show a task by stable key"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [epic: :string, key: :string])
    epic = opts[:epic] || Mix.raise(usage())
    key = opts[:key] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      task = TaskGraph.task_by_stable_key!(epic, key)

      TaskCommand.emit!(%{
        "stable_key" => task.stable_key,
        "slice_id" => task.id,
        "title" => task.title,
        "state" => to_string(task.state),
        "source_refs" => task.source_refs,
        "likely_files" => task.likely_files,
        "conflict_domains" => task.conflict_domains,
        "acceptance_criteria_count" => length(task.acceptance_criteria)
      })
    end)
  end

  defp usage, do: "usage: mix conveyor.task.show --epic EPIC_ID --key SLICE-001"
end
