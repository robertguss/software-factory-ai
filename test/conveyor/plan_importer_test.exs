defmodule Conveyor.Planning.PlanImporterTest do
  @moduledoc """
  Coverage for the one-time YAML -> DB migration (U7). Imports a `conveyor.plan@1` contract into
  DB rows and asserts the graph is materialized faithfully — including that dependencies are
  imported AS DECLARED (no linear-chain fabrication).
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, Plan, Project, Slice, TaskDependency}
  alias Conveyor.PlanContract
  alias Conveyor.Planning.PlanImporter

  defp slice(key, title) do
    %{
      "key" => key,
      "title" => title,
      "requirement_refs" => ["REQ-001"],
      "likely_files" => [],
      "conflict_domains" => [],
      "autonomy_ceiling" => "L1"
    }
  end

  defp result(overrides) do
    contract =
      Map.merge(
        %{
          "schema_version" => "conveyor.plan@1",
          "project" => %{"key" => "tp", "base_ref" => "main"},
          "goal" => "Test plan goal",
          "non_goals" => [],
          "requirements" => [
            %{"key" => "REQ-001", "text" => "r", "risk" => "low", "source_ref" => "p#r"}
          ],
          "acceptance_criteria" => [
            %{
              "key" => "AC-001",
              "text" => "a",
              "requirement_refs" => ["REQ-001"],
              "required_test_refs" => []
            }
          ],
          "verification_commands" => [],
          "decisions" => [],
          "slices" => [slice("SLICE-001", "First"), slice("SLICE-002", "Second")]
        },
        overrides
      )

    %PlanContract.Result{
      source_path: "/tmp/imported/conveyor.plan.json",
      contract: contract,
      contract_sha256: PlanContract.contract_sha256(contract)
    }
  end

  test "materializes project/plan/epic/slices from the contract" do
    imported = PlanImporter.import_result!(result(%{}), workspace_path: "/tmp/imported-ws")

    assert [project] = Ash.read!(Project, domain: Factory)
    assert project.name == "tp"
    assert imported.project.id == project.id

    assert [plan] = Ash.read!(Plan, domain: Factory)
    assert plan.intent == "Test plan goal"
    assert plan.status == :handoff_ready
    assert plan.contract_sha256 == result(%{}).contract_sha256

    assert [epic] = Ash.read!(Epic, domain: Factory)
    assert epic.plan_id == plan.id

    slices = Ash.read!(Slice, domain: Factory)
    assert Enum.map(slices, & &1.stable_key) |> Enum.sort() == ["SLICE-001", "SLICE-002"]
    # Imported tasks start :drafted — the human approval gate still applies before a run.
    assert Enum.all?(slices, &(&1.state == :drafted))
  end

  test "imports declared edges as TaskDependency rows" do
    overrides = %{
      "slices" => [slice("SLICE-001", "a"), slice("SLICE-002", "b"), slice("SLICE-003", "c")],
      "work_dependencies" => [
        %{"from" => "SLICE-001", "to" => "SLICE-003", "kind" => "execution_hard"}
      ]
    }

    imported = PlanImporter.import_result!(result(overrides), workspace_path: "/tmp/imported-ws")

    by_key = imported.slices_by_stable_key
    edges = Ash.read!(TaskDependency, domain: Factory)

    assert [edge] = edges
    assert edge.from_slice_id == by_key["SLICE-001"].id
    assert edge.to_slice_id == by_key["SLICE-003"].id
    assert edge.kind == :execution_hard
  end

  test "a contract with no work_dependencies imports zero edges (no fabricated chain)" do
    PlanImporter.import_result!(result(%{}), workspace_path: "/tmp/imported-ws")
    assert Ash.read!(TaskDependency, domain: Factory) == []
  end

  test "migrates the real beads_insight sample faithfully (equivalence proof)" do
    path = "samples/beads_insight/conveyor.plan.yml"
    {:ok, loaded} = PlanContract.load(path)
    expected_keys = Enum.map(loaded.contract["slices"], & &1["key"])
    expected_edges = Map.get(loaded.contract, "work_dependencies", [])

    imported = PlanImporter.import!(path)

    # The plan-level contract round-trips verbatim (acceptance/verification/decisions/non_goals).
    assert imported.plan.normalized_contract == loaded.contract
    assert imported.plan.contract_sha256 == loaded.contract_sha256

    slices = Ash.read!(Slice, domain: Factory)
    assert Enum.map(slices, & &1.stable_key) |> Enum.sort() == Enum.sort(expected_keys)

    # Edges are imported exactly as declared (no fabrication).
    assert length(Ash.read!(TaskDependency, domain: Factory)) == length(expected_edges)
  end
end
