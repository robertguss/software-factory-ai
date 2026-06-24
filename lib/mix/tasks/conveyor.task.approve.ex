defmodule Mix.Tasks.Conveyor.Task.Approve do
  @moduledoc """
  Approve a task (by stable key within an epic) — the human go-signal, run as the `Slice`
  `:drafted -> :approved` transition (KTD6). Fails non-zero (no crash) from a wrong state.

      mix conveyor.task.approve --epic EPIC_ID --key SLICE-001
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "Approve a task for running"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [epic: :string, key: :string])
    epic = opts[:epic] || Mix.raise(usage())
    key = opts[:key] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      task = TaskGraph.task_by_stable_key!(epic, key)
      approved = TaskGraph.approve_task(task.id)

      TaskCommand.emit!(%{
        "stable_key" => approved.stable_key,
        "slice_id" => approved.id,
        "state" => to_string(approved.state)
      })
    end)
  end

  defp usage, do: "usage: mix conveyor.task.approve --epic EPIC_ID --key SLICE-001"
end
