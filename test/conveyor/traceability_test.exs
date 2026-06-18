defmodule Conveyor.TraceabilityTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.PlanContract
  alias Conveyor.PlanImport
  alias Conveyor.Traceability

  @valid_example Path.expand("../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)

  setup do
    {:ok, contract_result} = PlanContract.load(@valid_example)

    project =
      Ash.create!(
        Project,
        %{
          name: "Traceability sample",
          local_path: "/tmp/traceability-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    %{project: project, contract_result: contract_result}
  end

  test "builds requirement to acceptance criterion to test maps", %{
    contract_result: contract_result,
    project: project
  } do
    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)

    result = Traceability.analyze_plan!(plan)

    assert result.status == :ready
    assert result.findings == []

    assert result.requirement_map["REQ-001"] == %{
             "requirement_ref" => "REQ-001",
             "status" => "covered",
             "acceptance_criteria" => ["AC-001"],
             "required_tests" => ["tests/test_tasks.py::test_create_defaults_completed_false"],
             "slices" => ["SLICE-001"],
             "covered_by_brief" => false,
             "covered" => true
           }

    assert result.coverage_summary["requirements"] == %{
             "total" => 1,
             "covered" => 1,
             "open" => 0,
             "with_acceptance_criteria" => 1,
             "with_required_tests" => 1
           }

    assert result.coverage_summary["traceability_percent"] == 100
  end

  test "flags an open requirement with no Slice or Brief coverage", %{
    contract_result: contract_result,
    project: project
  } do
    contract_result = append_open_untraced_requirement(contract_result)
    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)

    result = Traceability.analyze_plan!(plan)

    assert result.status == :blocked
    assert result.coverage_summary["requirements"]["open"] == 1
    assert result.coverage_summary["traceability_percent"] == 50

    assert Enum.any?(
             result.findings,
             &(&1["message"] == "Requirement REQ-002 is still open.")
           )

    assert Enum.any?(
             result.findings,
             &(&1["message"] == "Requirement REQ-002 has no Slice or Brief coverage.")
           )
  end

  test "flags a Slice with no source refs", %{
    contract_result: contract_result,
    project: project
  } do
    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Traceability epic", description: "Traceability checks."},
        domain: Factory
      )

    Ash.create!(
      Slice,
      %{
        epic_id: epic.id,
        title: "Unmapped cleanup",
        position: 2,
        source_refs: [],
        likely_files: ["app/main.py"],
        conflict_domains: ["tasks_api"]
      },
      domain: Factory
    )

    result = Traceability.analyze_plan!(plan)

    assert result.status == :blocked
    assert result.coverage_summary["slices"]["orphaned"] == 1

    assert Enum.any?(
             result.findings,
             &(&1["message"] =~ "has no source requirement, decision, bug, or improvement")
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
        contract_sha256: "sha256:" <> String.duplicate("8", 64)
    }
  end
end
