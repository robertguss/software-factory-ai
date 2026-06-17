defmodule Conveyor.PlanAuditorTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.PlanAudit
  alias Conveyor.Factory.Project
  alias Conveyor.PlanAuditor
  alias Conveyor.PlanContract
  alias Conveyor.PlanImport

  @valid_example Path.expand("../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)

  setup do
    {:ok, contract_result} = PlanContract.load(@valid_example)

    project =
      Ash.create!(
        Project,
        %{
          name: "Plan audit sample",
          local_path: "/tmp/plan-audit-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    %{project: project, contract_result: contract_result}
  end

  test "persists a ready PlanAudit for a traced plan", %{
    contract_result: contract_result,
    project: project
  } do
    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)

    result = PlanAuditor.audit_plan!(plan)

    assert result.decision == :ready
    assert result.score == 100
    assert result.findings == []
    assert result.scores["traceability"] == 100
    assert result.coverage_summary["traceability"]["traceability_percent"] == 100

    assert [audit] = Ash.read!(PlanAudit, domain: Factory)
    assert audit.id == result.audit.id
    assert audit.plan_id == plan.id
    assert audit.decision == :ready
    assert audit.score == 100
  end

  test "blocking findings force a blocked decision and stable persisted output", %{
    contract_result: contract_result,
    project: project
  } do
    contract_result = append_open_untraced_requirement(contract_result)
    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)

    first = PlanAuditor.audit_plan!(plan)
    second = PlanAuditor.audit_plan!(plan)

    assert first.decision == :blocked
    assert first.score < 100
    assert first.findings == second.findings
    assert first.scores == second.scores

    assert Enum.any?(
             first.findings,
             &(&1["message"] == "Requirement REQ-002 has no acceptance criteria.")
           )

    assert Enum.any?(
             first.findings,
             &(&1["message"] == "Requirement REQ-002 has no Slice or Brief coverage.")
           )

    assert Enum.all?(Ash.read!(PlanAudit, domain: Factory), &(&1.decision == :blocked))
  end

  test "unsupported autonomy ceiling produces a deterministic blocking finding", %{
    contract_result: %PlanContract.Result{} = contract_result,
    project: project
  } do
    contract =
      put_in(contract_result.contract, ["slices", Access.at(0), "autonomy_ceiling"], "L4")

    contract_result = %PlanContract.Result{contract_result | contract: contract}

    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)

    result = PlanAuditor.audit_plan!(plan)

    assert result.decision == :blocked
    assert result.scores["autonomy_readiness"] == 0

    assert Enum.any?(
             result.findings,
             &(&1["message"] == "Slice SLICE-001 exceeds Phase-1 autonomy readiness.")
           )
  end

  defp create_plan!(project, contract_result) do
    Ash.create!(
      Plan,
      %{
        project_id: project.id,
        title: "Complete tasks API",
        intent: "Allow tasks to be marked complete.",
        source_document: contract_result.source_path,
        normalized_contract: contract_result.contract,
        contract_sha256: contract_result.contract_sha256
      },
      domain: Factory
    )
  end

  defp append_open_untraced_requirement(%PlanContract.Result{} = contract_result) do
    contract =
      update_in(contract_result.contract, ["requirements"], fn requirements ->
        requirements ++
          [
            %{
              "key" => "REQ-002",
              "text" => "Incomplete tasks remain visible in list responses.",
              "risk" => "medium",
              "source_ref" => "plan.md#requirement-req-002",
              "status" => "open"
            }
          ]
      end)

    %PlanContract.Result{
      contract_result
      | contract: contract,
        contract_sha256: "sha256:" <> String.duplicate("7", 64)
    }
  end
end
