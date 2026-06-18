defmodule Conveyor.PlanImportTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Requirement
  alias Conveyor.PlanContract
  alias Conveyor.PlanImport

  @valid_example Path.expand("../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)

  setup do
    contract_result = contract_result_with_open_requirement()

    project =
      Ash.create!(
        Project,
        %{
          name: "Plan import sample",
          local_path: "/tmp/plan-import-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
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

    %{contract_result: contract_result, plan: plan}
  end

  test "imports requirements and human decisions with trace anchors", %{
    contract_result: contract_result,
    plan: plan
  } do
    result = PlanImport.import_requirements_and_decisions!(plan, contract_result)

    assert Enum.map(result.requirements, & &1.stable_key) == ["REQ-001", "REQ-002"]
    assert Enum.map(result.human_decisions, & &1.stable_key) == ["DEC-001"]
    assert Enum.map(result.open_requirements, & &1.stable_key) == ["REQ-002"]

    requirements = Ash.read!(Requirement, domain: Factory) |> Enum.sort_by(& &1.stable_key)
    decisions = Ash.read!(HumanDecision, domain: Factory)

    assert [
             %Requirement{
               stable_key: "REQ-001",
               section_ref: "plan.md#requirement-req-001",
               source_span: %{},
               contract_sha256: contract_sha256,
               status: :covered,
               risk: "low"
             },
             %Requirement{
               stable_key: "REQ-002",
               section_ref: "plan.md#requirement-req-002",
               source_span: %{},
               contract_sha256: contract_sha256,
               status: :open,
               risk: "medium"
             }
           ] = requirements

    assert contract_sha256 == contract_result.contract_sha256

    assert [
             %HumanDecision{
               stable_key: "DEC-001",
               section_ref: "decisions/DEC-001",
               source_span: %{},
               contract_sha256: ^contract_sha256,
               status: :active
             }
           ] = decisions
  end

  test "re-import is idempotent by plan and stable key", %{
    contract_result: contract_result,
    plan: plan
  } do
    first = PlanImport.import_requirements_and_decisions!(plan, contract_result)
    second = PlanImport.import_requirements_and_decisions!(plan, contract_result)

    assert Enum.map(first.requirements, & &1.id) == Enum.map(second.requirements, & &1.id)
    assert Enum.map(first.human_decisions, & &1.id) == Enum.map(second.human_decisions, & &1.id)
    assert length(Ash.read!(Requirement, domain: Factory)) == 2
    assert length(Ash.read!(HumanDecision, domain: Factory)) == 1
  end

  defp contract_result_with_open_requirement do
    {:ok, result} = PlanContract.load(@valid_example)

    contract =
      update_in(result.contract, ["requirements"], fn requirements ->
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
      result
      | contract: contract,
        contract_sha256: "sha256:" <> String.duplicate("9", 64)
    }
  end
end
