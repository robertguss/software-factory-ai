defmodule Mix.Tasks.Conveyor.Task.Create do
  @moduledoc """
  Create a task (Slice) under an epic. Emits the new task's stable key as JSON.

      mix conveyor.task.create --epic EPIC_ID --title "Loader" \\
        --files lib/a.ex,lib/b.ex --conflict-domains schema --source-refs REQ-001 --autonomy L1
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "Create a task under an epic"

  @switches [
    epic: :string,
    title: :string,
    files: :string,
    conflict_domains: :string,
    source_refs: :string,
    autonomy: :string
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)
    epic = opts[:epic] || Mix.raise(usage())
    title = opts[:title] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      task =
        TaskGraph.create_task(%{
          epic_id: epic,
          title: title,
          likely_files: TaskCommand.csv(opts[:files]),
          conflict_domains: TaskCommand.csv(opts[:conflict_domains]),
          source_refs: TaskCommand.csv(opts[:source_refs]),
          autonomy_level: opts[:autonomy] || "L1"
        })

      TaskCommand.emit!(%{
        "stable_key" => task.stable_key,
        "slice_id" => task.id,
        "state" => to_string(task.state)
      })
    end)
  end

  defp usage,
    do:
      "usage: mix conveyor.task.create --epic EPIC_ID --title TITLE [--files a,b] [--source-refs REQ-1]"
end
