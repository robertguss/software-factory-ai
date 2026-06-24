defmodule Conveyor.Planning.ContractBuilderTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.PlanContract
  alias Conveyor.Planning.ContractBuilder
  alias Conveyor.TaskGraph

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "beads_insight", local_path: "/tmp/contract-builder", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Contract builder plan",
          intent: "Build a read-only insight CLI.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("seed")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Epic", description: "Slices."},
        domain: Factory
      )

    %{plan: plan, epic: epic, project: project}
  end

  test "builds a schema-valid normalized_contract from rows", %{plan: plan, epic: epic} do
    one =
      TaskGraph.create_task(%{
        epic_id: epic.id,
        title: "Core commands",
        source_refs: ["REQ-001"],
        likely_files: ["br_insight"],
        conflict_domains: ["schema"],
        autonomy_level: "L2"
      })

    TaskGraph.set_acceptance(one.id, [
      %{
        "id" => "AC-001",
        "text" => "Counts are stable.",
        "requirement_refs" => ["REQ-001"],
        "required_test_refs" => ["tests/test_loader.py::test_counts"]
      }
    ])

    TaskGraph.create_task(%{epic_id: epic.id, title: "Docs", source_refs: ["REQ-002"]})

    contract = ContractBuilder.build(plan)

    assert contract["schema_version"] == "conveyor.plan@1"
    assert contract["project"] == %{"key" => "beads_insight", "base_ref" => "main"}
    assert contract["goal"] == "Build a read-only insight CLI."
    assert contract["non_goals"] == []
    assert contract["requirements"] == []
    assert contract["verification_commands"] == []
    assert contract["decisions"] == []

    assert [first, second] = contract["slices"]
    assert first["key"] == "SLICE-001"
    assert first["title"] == "Core commands"
    assert first["requirement_refs"] == ["REQ-001"]
    assert first["likely_files"] == ["br_insight"]
    assert first["conflict_domains"] == ["schema"]
    assert first["autonomy_ceiling"] == "L2"
    assert second["key"] == "SLICE-002"

    assert [%{"id" => "AC-001", "requirement_refs" => ["REQ-001"]}] =
             contract["acceptance_criteria"]
  end

  test "yields a canonical contract_sha256 that is deterministic", %{plan: plan, epic: epic} do
    TaskGraph.create_task(%{epic_id: epic.id, title: "Only", source_refs: ["REQ-001"]})

    first = PlanContract.contract_sha256(ContractBuilder.build(plan))
    second = PlanContract.contract_sha256(ContractBuilder.build(plan))

    assert first == second
    assert String.starts_with?(first, "sha256:")
  end

  test "aggregates acceptance criteria across slices", %{plan: plan, epic: epic} do
    a = TaskGraph.create_task(%{epic_id: epic.id, title: "A", source_refs: ["REQ-001"]})
    b = TaskGraph.create_task(%{epic_id: epic.id, title: "B", source_refs: ["REQ-002"]})

    TaskGraph.set_acceptance(a.id, [
      %{
        "id" => "AC-001",
        "text" => "a",
        "requirement_refs" => ["REQ-001"],
        "required_test_refs" => ["t::a"]
      }
    ])

    TaskGraph.set_acceptance(b.id, [
      %{
        "id" => "AC-002",
        "text" => "b",
        "requirement_refs" => ["REQ-002"],
        "required_test_refs" => ["t::b"]
      }
    ])

    contract = ContractBuilder.build(plan)
    ids = Enum.map(contract["acceptance_criteria"], & &1["id"])

    assert Enum.sort(ids) == ["AC-001", "AC-002"]
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
