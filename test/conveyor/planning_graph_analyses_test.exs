defmodule Conveyor.PlanningGraphAnalysesTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.GraphAnalyses

  test "passes a traceable graph with atomicity, scope, anti-confetti, and oracle evidence" do
    result = GraphAnalyses.run(valid_graph())

    assert result.status == :passed
    assert result.scope_delta == :scope_preserved
    assert result.findings == []
  end

  test "emits deterministic findings for graph analysis failures" do
    graph =
      valid_graph()
      |> put_in([:atomicity_groups], [
        %{key: "ATOMIC-BROKEN", member_keys: ["SLC-A", "SLC-MISSING"], forbidden_intermediate_states: ["partial_write"]}
      ])
      |> put_in([:slices], [
        %{
          stable_key: "SLC-A",
          requirement_refs: ["REQ-001"],
          acceptance_refs: [],
          authorized_change_globs: ["app/**", "secrets/**"],
          oracle_feasible?: false,
          risk_domains: ["db", "api", "ui", "ops"]
        },
        %{
          stable_key: "SLC-B",
          requirement_refs: [],
          acceptance_refs: [],
          authorized_change_globs: ["app/**"],
          oracle_feasible?: true,
          risk_domains: ["api"]
        }
      ])
      |> put_in([:work_dependencies], [
        %{from: "SLC-A", to: "SLC-B"},
        %{from: "SLC-B", to: "SLC-A"},
        %{from: "SLC-A", to: "SLC-A"}
      ])

    result = GraphAnalyses.run(graph)

    assert result.status == :blocked
    assert result.scope_delta == :scope_expanded

    assert Enum.map(result.findings, & &1.rule_key) == [
             "atomicity_group_missing_member",
             "unapproved_scope_delta",
             "traceability_gap",
             "traceability_gap",
             "slice_too_small",
             "slice_too_small",
             "coordination_overhead",
             "false_parallelism",
             "risk_domains",
             "oracle_infeasible"
           ]

    assert Enum.all?(result.findings, &(&1.severity == :blocking))
  end

  defp valid_graph do
    %{
      approved_scope_globs: ["app/**", "test/**"],
      requirements: [%{key: "REQ-001"}],
      acceptance_criteria: [%{key: "AC-001", requirement_ref: "REQ-001"}],
      obligations: [%{"acceptance_ref" => "AC-001"}],
      slices: [
        %{
          stable_key: "SLC-A",
          requirement_refs: ["REQ-001"],
          acceptance_refs: ["AC-001"],
          authorized_change_globs: ["app/**", "test/**"],
          oracle_feasible?: true,
          risk_domains: ["api"]
        }
      ],
      atomicity_groups: [
        %{key: "ATOMIC-A", member_keys: ["SLC-A"], forbidden_intermediate_states: ["partial_write"]}
      ],
      work_dependencies: []
    }
  end
end
