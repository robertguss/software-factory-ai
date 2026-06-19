defmodule Conveyor.PlanningInterfaceGraphTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.InterfaceGraph

  test "resolves provider consumer compatibility without creating work edges" do
    result =
      InterfaceGraph.analyze(%{
        contracts: [
          contract("db.tasks.completed", "SLC-SCHEMA", "1")
        ],
        bindings: [
          %{slice_key: "SLC-SCHEMA", interface_key: "db.tasks.completed", direction: "provides"},
          %{
            slice_key: "SLC-FILTER",
            interface_key: "db.tasks.completed",
            direction: "requires",
            required_version_range: ">=1 <2"
          },
          %{slice_key: "SLC-SCHEMA", interface_key: "db.tasks.completed", direction: "modifies"}
        ]
      })

    assert result.status == :ready
    assert result.pairwise_work_edges == []
    assert result.diagnostics == []

    assert result.readiness == [
             %{
               interface_key: "db.tasks.completed",
               provider_slice_key: "SLC-SCHEMA",
               consumer_slice_key: "SLC-FILTER",
               provider_version: "1",
               required_version_range: ">=1 <2",
               status: :ready,
               lock_level: "review_required",
               compatibility_policy: "migration_required"
             }
           ]
  end

  test "blocks missing providers and incompatible consumer versions" do
    result =
      InterfaceGraph.analyze(%{
        contracts: [
          contract("db.tasks.completed", "SLC-SCHEMA", "1")
        ],
        bindings: [
          %{
            slice_key: "SLC-FILTER",
            interface_key: "db.tasks.completed",
            direction: "requires",
            required_version_range: ">=2 <3"
          },
          %{
            slice_key: "SLC-REPORT",
            interface_key: "db.tasks.archived",
            direction: "requires",
            required_version_range: ">=1 <2"
          }
        ]
      })

    assert result.status == :blocked

    assert %{
             rule_key: "interface_version_incompatible",
             severity: :blocking,
             subject_key: "SLC-FILTER -> db.tasks.completed"
           } in result.diagnostics

    assert %{
             rule_key: "interface_provider_missing",
             severity: :blocking,
             subject_key: "SLC-REPORT -> db.tasks.archived"
           } in result.diagnostics
  end

  defp contract(interface_key, owner_slice_key, version) do
    %{
      interface_key: interface_key,
      kind: "db_column",
      stability: "internal_cross_slice",
      lock_level: "review_required",
      compatibility_policy: "migration_required",
      owner_slice_key: owner_slice_key,
      version: version,
      lifecycle: "active"
    }
  end
end
