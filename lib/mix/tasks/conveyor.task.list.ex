defmodule Mix.Tasks.Conveyor.Task.List do
  @moduledoc """
  List an epic's tasks in position order.

      mix conveyor.task.list --epic EPIC_ID
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "List tasks in an epic"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [epic: :string])
    epic = opts[:epic] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      tasks = Enum.map(TaskGraph.list_tasks(epic), &task_view/1)
      TaskCommand.emit!(%{"tasks" => tasks})
    end)
  end

  defp task_view(task) do
    %{
      "stable_key" => task.stable_key,
      "slice_id" => task.id,
      "title" => task.title,
      "state" => to_string(task.state)
    }
  end

  defp usage, do: "usage: mix conveyor.task.list --epic EPIC_ID"
end
