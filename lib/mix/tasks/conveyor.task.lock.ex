defmodule Mix.Tasks.Conveyor.Task.Lock do
  @moduledoc """
  Lock a task (by stable key within an epic): compile the plan's contract from rows and materialize
  the gate-valid `AgentBrief`/`TestPack`/`ContractLock` (KTD3). Fails non-zero with the readiness
  findings if the task is not gate-ready (e.g. missing acceptance criteria).

      mix conveyor.task.lock --epic EPIC_ID --key SLICE-001
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "Lock a task's vetted contract"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [epic: :string, key: :string])
    epic = opts[:epic] || Mix.raise(usage())
    key = opts[:key] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      task = TaskGraph.task_by_stable_key!(epic, key)
      locked = TaskGraph.lock_task(task.id)

      TaskCommand.emit!(%{
        "stable_key" => locked.stable_key,
        "slice_id" => locked.id,
        "state" => to_string(locked.state),
        "locked" => true
      })
    end)
  end

  defp usage, do: "usage: mix conveyor.task.lock --epic EPIC_ID --key SLICE-001"
end
