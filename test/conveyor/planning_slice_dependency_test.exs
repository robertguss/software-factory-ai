defmodule Conveyor.PlanningSliceDependencyTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SliceDependency

  test "materializes only execution and integration work edges with provenance" do
    graph =
      SliceDependency.analyze(%{
        slices: [
          %{stable_key: "SLC-SCHEMA", status: "active"},
          %{stable_key: "SLC-FILTER", status: "active"},
          %{stable_key: "SLC-UI", status: "active"}
        ],
        dependencies: [
          dependency("SLC-SCHEMA", "SLC-FILTER", "execution_hard"),
          dependency("SLC-FILTER", "SLC-UI", "integration_order"),
          dependency("SLC-SCHEMA", "SLC-UI", "interface_readiness"),
          dependency("SLC-UI", "SLC-SCHEMA", "likely_overlap")
        ],
        scheduling_hints: [
          %{from: "SLC-UI", to: "SLC-FILTER", reason: "likely_files overlap"}
        ]
      })

    assert graph.status == :valid
    assert Enum.map(graph.work_edges, &{&1.from, &1.to, &1.kind}) == [
             {"SLC-SCHEMA", "SLC-FILTER", :execution_hard},
             {"SLC-FILTER", "SLC-UI", :integration_order}
           ]

    assert Enum.all?(graph.work_edges, &(&1.rationale == "Ordering rationale"))
    assert Enum.all?(graph.work_edges, &(&1.source_anchor_refs == ["SRC-EDGE"]))
    assert Enum.all?(graph.work_edges, &(&1.origin == :deterministic_derived))
    assert Enum.all?(graph.work_edges, &(&1.confidence == 1.0))
    assert graph.scheduling_hints == [%{from: "SLC-UI", to: "SLC-FILTER", reason: "likely_files overlap"}]
    assert graph.ignored_dependency_kinds == [:interface_readiness, :likely_overlap]
    assert graph.diagnostics == []
  end

  test "reports cycles and unreachable active nodes" do
    cyclic =
      SliceDependency.analyze(%{
        slices: [
          %{stable_key: "SLC-A", status: "active"},
          %{stable_key: "SLC-B", status: "active"},
          %{stable_key: "SLC-C", status: "active"}
        ],
        dependencies: [
          dependency("SLC-A", "SLC-B", "execution_hard"),
          dependency("SLC-B", "SLC-A", "execution_hard")
        ]
      })

    assert cyclic.status == :invalid

    assert %{rule_key: "work_graph_cycle", severity: :blocking, subject_key: "SLC-A -> SLC-B -> SLC-A"} in cyclic.diagnostics
    assert %{rule_key: "unreachable_active_slice", severity: :blocking, subject_key: "SLC-C"} in cyclic.diagnostics
  end

  defp dependency(from, to, kind) do
    %{
      from: from,
      to: to,
      kind: kind,
      rationale: "Ordering rationale",
      source_anchor_refs: ["SRC-EDGE"],
      origin: "deterministic_derived",
      confidence: 1.0
    }
  end
end
