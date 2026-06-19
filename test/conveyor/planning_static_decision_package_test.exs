defmodule Conveyor.PlanningStaticDecisionPackageTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.StaticDecisionPackage

  test "assembles required static compiler artifacts without execution authority" do
    package =
      StaticDecisionPackage.build(%{
        normalized_plan: %{plan_key: "plan-1"},
        claims: [%{subject_pointer: "/requirements/0"}],
        constraints: [%{key: "CON-001"}],
        candidate_comparison: [%{candidate_key: "primary"}],
        work_graph: %{schema_version: "conveyor.work_graph@2"},
        interfaces: [%{interface_key: "db.tasks.completed"}],
        decisions: [%{human_decision_ref: "DEC-001"}],
        derivation_graph: [%{"consumer_artifact_id" => "work_graph:1"}],
        structural_dry_run: %{waves: [["SLC-A"]]},
        scope_delta: :scope_preserved,
        oracle_warnings: []
      })

    assert package.status == :complete
    assert package.package_kind == :static_decision_package
    assert package.authority_effect == :none
    assert package.creates_contract_lock? == false
    assert package.creates_approval? == false
    assert package.creates_ready_slice? == false
    assert package.artifact_digest =~ ~r/^sha256:[0-9a-f]{64}$/

    assert Map.keys(package.artifacts) |> Enum.sort() == [
             :candidate_comparison,
             :claims,
             :constraints,
             :decisions,
             :derivation_graph,
             :interfaces,
             :normalized_plan,
             :oracle_warnings,
             :scope_delta,
             :structural_dry_run,
             :work_graph
           ]
  end

  test "reports missing required artifacts instead of emitting a partial package" do
    result = StaticDecisionPackage.build(%{normalized_plan: %{plan_key: "plan-1"}})

    assert result.status == :blocked
    assert result.artifacts == nil
    assert "work_graph" in result.missing_artifacts
    assert "derivation_graph" in result.missing_artifacts
  end
end
