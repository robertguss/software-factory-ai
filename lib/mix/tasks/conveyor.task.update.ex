defmodule Mix.Tasks.Conveyor.Task.Update do
  @moduledoc """
  Update a task's authoring attributes (by stable key within an epic).

      mix conveyor.task.update --epic EPIC_ID --key SLICE-001 --title "New title" \\
        --files lib/a.ex --source-refs REQ-001
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "Update a task's attributes"

  @switches [
    epic: :string,
    key: :string,
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
    key = opts[:key] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      task = TaskGraph.task_by_stable_key!(epic, key)
      updated = TaskGraph.update_task(task.id, update_attrs(opts))

      TaskCommand.emit!(%{
        "stable_key" => updated.stable_key,
        "slice_id" => updated.id,
        "title" => updated.title,
        "state" => to_string(updated.state)
      })
    end)
  end

  defp update_attrs(opts) do
    [
      {:title, opts[:title]},
      {:likely_files, opts[:files] && TaskCommand.csv(opts[:files])},
      {:conflict_domains, opts[:conflict_domains] && TaskCommand.csv(opts[:conflict_domains])},
      {:source_refs, opts[:source_refs] && TaskCommand.csv(opts[:source_refs])},
      {:autonomy_level, opts[:autonomy]}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp usage,
    do: "usage: mix conveyor.task.update --epic EPIC_ID --key SLICE-001 [--title T] [--files a,b]"
end
