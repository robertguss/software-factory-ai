defmodule Mix.Tasks.Conveyor.Epic.Create do
  @moduledoc """
  Add an `Epic` to an existing `Plan` (plans may hold several epics; `conveyor.plan.create` only
  makes the first). Emits the new epic id, its plan id, and status as JSON.

      mix conveyor.epic.create --plan PLAN_UUID --title "Second epic" \\
        --description "Additional slices." [--risk high]
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan

  @shortdoc "Add an epic to an existing plan"

  @switches [plan: :string, title: :string, description: :string, risk: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)
    plan_id = opts[:plan] || Mix.raise(usage())
    title = opts[:title] || Mix.raise(usage())
    description = opts[:description] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      # Resolve the plan first so an unknown UUID is a clean error rather than an opaque FK
      # violation (`Ash.get!` raises `Ash.Error.Invalid`, which `guard` maps to a non-zero exit).
      plan = Ash.get!(Plan, plan_id, domain: Factory)

      epic =
        Ash.create!(
          Epic,
          %{
            plan_id: plan.id,
            title: title,
            description: description,
            risk: opts[:risk] || "medium"
          },
          domain: Factory
        )

      TaskCommand.emit!(%{
        "epic_id" => epic.id,
        "plan_id" => plan.id,
        "status" => to_string(epic.status)
      })
    end)
  end

  defp usage,
    do:
      "usage: mix conveyor.epic.create --plan PLAN_UUID --title TITLE --description DESC [--risk RISK]"
end
