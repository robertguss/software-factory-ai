defmodule Mix.Tasks.Conveyor.Plan.Create do
  @moduledoc """
  Create a runnable Plan shell — a `Project` (found-or-created by workspace path), a `Plan`, and a
  first `Epic` — in one command, so an operator (or external AI) can author slices into it with no
  hand-seeding. Emits the created IDs and the plan's `contract_sha256` as JSON.

      mix conveyor.plan.create --workspace-path /repo --title "Insight CLI" \\
        --intent "Build the read-only insight CLI." \\
        --verification-command "pytest -q"

  The plan is created as a `:draft` carrying a minimal `conveyor.plan@1` `normalized_contract`
  (empty slices/criteria, `verification_commands` from `--verification-command`, default
  `pytest -q`). Authoring (`task.create`/`task.dep`/`task.acceptance`) fills in the slices and
  criteria; the first `task.lock` compiles the contract from those rows and advances the plan to
  `:handoff_ready`. Carrying `verification_commands` at create time keeps the shell runnable —
  `task.acceptance` authors criteria incrementally but never the verification commands.
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.PlanContract

  @shortdoc "Create a runnable Plan + Epic shell for incremental authoring"

  @schema_version "conveyor.plan@1"
  @default_verification_argv ["pytest", "-q"]

  @switches [
    workspace_path: :string,
    title: :string,
    intent: :string,
    verification_command: :keep,
    epic_title: :string,
    project_name: :string
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)
    workspace_path = opts[:workspace_path] || Mix.raise(usage())
    title = opts[:title] || Mix.raise(usage())
    intent = opts[:intent] || Mix.raise(usage())

    TaskCommand.guard(fn ->
      project = find_or_create_project!(workspace_path, opts[:project_name] || "conveyor-plan")
      contract = build_contract(project, intent, verification_commands(opts))

      plan =
        Ash.create!(
          Plan,
          %{
            project_id: project.id,
            title: title,
            intent: intent,
            source_document: "cli:conveyor.plan.create",
            normalized_contract: contract,
            contract_sha256: PlanContract.contract_sha256(contract),
            # Draft so the first `task.lock` compiles the contract from the authored rows before
            # the `plans_freeze_contract_after_draft` trigger freezes it.
            status: :draft
          },
          domain: Factory
        )

      epic =
        Ash.create!(
          Epic,
          %{
            plan_id: plan.id,
            title: opts[:epic_title] || title,
            # `Epic.description` is required and non-nullable; derive it (mirroring `PlanImporter`'s
            # "Imported Conveyor plan for …") rather than leaving it nil.
            description: "Conveyor plan for #{title}"
          },
          domain: Factory
        )

      TaskCommand.emit!(%{
        "project_id" => project.id,
        "plan_id" => plan.id,
        "epic_id" => epic.id,
        "contract_sha256" => plan.contract_sha256
      })
    end)
  end

  # Find-or-create by `local_path` (mirrors `PlanImporter`'s reuse-by-`local_path` behavior) so
  # repeated calls on one workspace add plans without duplicating the project.
  defp find_or_create_project!(workspace_path, project_name) do
    case Project |> Ash.read!(domain: Factory) |> Enum.find(&(&1.local_path == workspace_path)) do
      nil ->
        Ash.create!(Project, %{name: project_name, local_path: workspace_path}, domain: Factory)

      existing ->
        existing
    end
  end

  # A minimal but valid-shaped `conveyor.plan@1` skeleton — the same shape `ContractBuilder`
  # recompiles at lock time, but carrying `verification_commands` so the shell is runnable.
  defp build_contract(project, intent, verification_commands) do
    %{
      "schema_version" => @schema_version,
      "project" => %{"key" => project.name, "base_ref" => project.default_branch},
      "goal" => intent,
      "non_goals" => [],
      "requirements" => [],
      "acceptance_criteria" => [],
      "verification_commands" => verification_commands,
      "decisions" => [],
      "slices" => []
    }
  end

  defp verification_commands(opts) do
    case Keyword.get_values(opts, :verification_command) do
      [] -> [command_entry(@default_verification_argv)]
      raw -> Enum.map(raw, &command_entry(String.split(&1, ~r/\s+/, trim: true)))
    end
  end

  defp command_entry(argv),
    do: %{"key" => List.first(argv), "argv" => argv, "profile" => "verify"}

  defp usage,
    do:
      "usage: mix conveyor.plan.create --workspace-path PATH --title TITLE --intent INTENT " <>
        "[--verification-command CMD] [--epic-title TITLE] [--project-name NAME]"
end
