defmodule Mix.Tasks.Conveyor.Task.Acceptance do
  @moduledoc """
  Author an acceptance criterion onto a task (by stable key within an epic). Appends to the task's
  existing criteria — the source `ContractBuilder` compiles into `Plan.normalized_contract` (KTD8).

      mix conveyor.task.acceptance add --epic EPIC_ID --key SLICE-001 \\
        --id AC-001 --text "Counts are stable across reloads." \\
        --requirement REQ-001 --test tests/test_loader.py::test_counts \\
        --falsifies "counts change when the same corpus is reloaded"
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.TaskGraph

  @shortdoc "Add an acceptance criterion to a task"

  @switches [
    epic: :string,
    key: :string,
    id: :string,
    text: :string,
    requirement: :keep,
    test: :keep,
    falsifies: :string
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    unless List.first(rest) == "add", do: Mix.raise(usage())
    epic = opts[:epic] || Mix.raise(usage())
    key = opts[:key] || Mix.raise(usage())
    id = opts[:id] || Mix.raise(usage())
    text = opts[:text] || Mix.raise(usage())

    requirements = Keyword.get_values(opts, :requirement)
    tests = Keyword.get_values(opts, :test)

    TaskCommand.guard(fn ->
      task = TaskGraph.task_by_stable_key!(epic, key)
      criterion = criterion(id, text, requirements, tests, opts[:falsifies])
      updated = TaskGraph.set_acceptance(task.id, task.acceptance_criteria ++ [criterion])

      TaskCommand.emit!(%{
        "stable_key" => updated.stable_key,
        "acceptance_criteria_count" => length(updated.acceptance_criteria),
        "added" => id
      })
    end)
  end

  defp criterion(id, text, requirements, tests, falsifies) do
    base = %{
      "id" => id,
      "text" => text,
      "requirement_refs" => requirements,
      "required_test_refs" => tests
    }

    if falsifies do
      Map.put(base, "falsifying_conditions", [
        %{
          "acceptance_criterion_id" => id,
          "condition" => falsifies,
          "required_test_refs" => tests
        }
      ])
    else
      base
    end
  end

  defp usage,
    do:
      "usage: mix conveyor.task.acceptance add --epic EPIC_ID --key SLICE-001 --id AC-001 --text TEXT --requirement REQ-1 --test PATH::t [--falsifies COND]"
end
