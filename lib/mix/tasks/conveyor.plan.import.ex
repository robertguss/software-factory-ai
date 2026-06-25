defmodule Mix.Tasks.Conveyor.Plan.Import do
  @moduledoc """
  Import a whole plan document into DB rows — Project + Plan + Epic + Slices + dependency edges —
  via `Conveyor.Planning.PlanImporter`. Emits the created IDs and slice count as JSON.

      mix conveyor.plan.import samples/beads_insight/conveyor.plan.yml
      mix conveyor.plan.import path/to/plan.md --workspace-path /abs/repo

  Accepts the same inputs as `Conveyor.PlanContract.load/1`: a `.json`/`.yml`/`.yaml` contract, a
  markdown plan with a sidecar `conveyor.plan.*`, or a fenced `conveyor-plan@1` block. `Project` is
  found-or-created by workspace path (`--workspace-path`, defaulting to the document's directory),
  mirroring `PlanImporter`'s reuse-by-`local_path` behavior. A schema-invalid, cyclic, or
  dangling-reference graph fails the load before any row is written.
  """

  use Mix.Task

  alias Conveyor.CLI.TaskCommand
  alias Conveyor.PlanContract
  alias Conveyor.Planning.PlanImporter

  @shortdoc "Import a plan document into DB rows"

  @switches [workspace_path: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, rest, _invalid} = OptionParser.parse(argv, strict: @switches)
    doc = List.first(rest) || Mix.raise(usage())

    TaskCommand.guard(fn ->
      # Load explicitly (rather than `PlanImporter.import!/2`) so a contract error surfaces as a
      # clean non-zero exit instead of an uncaught `MatchError`. `load/1` validates the DAG before
      # `import_result!/2` writes any Project/Plan/Epic/Slice row, so a bad graph persists nothing.
      case PlanContract.load(doc) do
        {:ok, result} ->
          imported = PlanImporter.import_result!(result, import_opts(opts))

          TaskCommand.emit!(%{
            "project_id" => imported.project.id,
            "plan_id" => imported.plan.id,
            "epic_id" => imported.epic.id,
            "slice_count" => map_size(imported.slices_by_stable_key),
            "contract_sha256" => imported.plan.contract_sha256
          })

        {:error, %PlanContract.Error{} = error} ->
          TaskCommand.fail!(error.message, :malformed_artifact_or_schema_failure)
      end
    end)
  end

  defp import_opts(opts) do
    case opts[:workspace_path] do
      nil -> []
      path -> [workspace_path: path]
    end
  end

  defp usage,
    do: "usage: mix conveyor.plan.import <plan-doc> [--workspace-path PATH]"
end
