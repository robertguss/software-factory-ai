defmodule Mix.Tasks.Conveyor.PlanAudit do
  @moduledoc """
  Audits a normalized Conveyor plan contract.

      mix conveyor.plan_audit PLAN.md
      mix conveyor.plan_audit conveyor.plan.yml
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.PlanAuditor
  alias Conveyor.PlanAuditReport
  alias Conveyor.PlanContract
  alias Conveyor.PlanImport

  @shortdoc "Audit a normalized Conveyor plan contract"

  @impl Mix.Task
  def run([path]) do
    Mix.Task.run("app.start")

    case PlanContract.load(path) do
      {:ok, contract_result} ->
        result = audit_contract!(contract_result)
        Mix.shell().info(PlanAuditReport.format(result))
        exit_fun().(exit_code(result))

      {:error, error} ->
        Mix.shell().error(error.message)
        exit_fun().(ExitCodes.fetch!(:malformed_artifact_or_schema_failure))
    end
  end

  def run(_args) do
    Mix.raise("usage: mix conveyor.plan_audit PLAN.md")
  end

  defp audit_contract!(contract_result) do
    project = create_project!(contract_result)
    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)
    PlanAuditor.audit_plan!(plan)
  end

  defp create_project!(%PlanContract.Result{contract: contract, source_path: source_path}) do
    project = Map.fetch!(contract, "project")
    local_path = Path.dirname(source_path)

    attrs = %{
      name: Map.fetch!(project, "key"),
      local_path: local_path,
      default_branch: Map.fetch!(project, "base_ref")
    }

    case find_one(Project, &(&1.local_path == local_path)) do
      nil -> Ash.create!(Project, attrs, domain: Factory)
      existing -> Ash.update!(existing, attrs, domain: Factory)
    end
  end

  defp create_plan!(project, %PlanContract.Result{} = contract_result) do
    attrs = %{
      project_id: project.id,
      title: "#{contract_result.contract["project"]["key"]} plan",
      intent: Map.fetch!(contract_result.contract, "goal"),
      source_document: contract_result.source_path,
      normalized_contract: contract_result.contract,
      contract_sha256: contract_result.contract_sha256
    }

    case find_one(
           Plan,
           &(&1.project_id == project.id and &1.contract_sha256 == contract_result.contract_sha256)
         ) do
      nil -> Ash.create!(Plan, attrs, domain: Factory)
      existing -> Ash.update!(existing, attrs, domain: Factory)
    end
  end

  defp find_one(resource, predicate) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(predicate)
  end

  defp exit_code(%PlanAuditor.Result{decision: :ready}), do: ExitCodes.fetch!(:success)
  defp exit_code(%PlanAuditor.Result{}), do: ExitCodes.fetch!(:plan_or_readiness_blocked)

  defp exit_fun do
    Process.get(:conveyor_plan_audit_exit_fun, &System.halt/1)
  end
end
