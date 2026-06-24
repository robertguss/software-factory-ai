defmodule Mix.Tasks.Conveyor.Task.Ready do
  @moduledoc """
  List the tasks in an epic that are ready to run — every execution-hard predecessor is satisfied.

      mix conveyor.task.ready --epic EPIC_ID
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "List ready tasks in an epic"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [epic: :string])
    epic = opts[:epic] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      ready =
        Enum.map(TaskGraph.ready_tasks(epic), fn task ->
          %{"stable_key" => task.stable_key, "slice_id" => task.id, "title" => task.title}
        end)

      TaskCommand.emit!(%{"ready" => ready})
    end)
  end

  defp usage, do: "usage: mix conveyor.task.ready --epic EPIC_ID"
end
