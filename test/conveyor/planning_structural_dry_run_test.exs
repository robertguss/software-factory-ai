defmodule Conveyor.PlanningStructuralDryRunTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.StructuralDryRun

  test "computes waves, fan-in/out, critical path, and conflict hints without economics" do
    result =
      StructuralDryRun.run(%{
        slices: [
          %{stable_key: "SLC-A", conflict_domains: ["tasks"]},
          %{stable_key: "SLC-B", conflict_domains: ["tasks"]},
          %{stable_key: "SLC-C", conflict_domains: ["reports"]}
        ],
        work_edges: [
          %{from: "SLC-A", to: "SLC-B", kind: :execution_hard},
          %{from: "SLC-A", to: "SLC-C", kind: :integration_order}
        ]
      })

    assert result.status == :ok
    assert result.waves == [["SLC-A"], ["SLC-B", "SLC-C"]]
    assert result.fan_in == %{"SLC-A" => 0, "SLC-B" => 1, "SLC-C" => 1}
    assert result.fan_out == %{"SLC-A" => 2, "SLC-B" => 0, "SLC-C" => 0}
    assert result.critical_path == ["SLC-A", "SLC-B"]
    assert result.conflict_domain_hints == [%{domain: "tasks", slice_keys: ["SLC-A", "SLC-B"]}]
    assert result.cost_time_estimate == :insufficient_history
  end

  test "impact preview fails wide on low confidence derivation" do
    index = %{
      artifact_inputs: [
        %{
          "consumer_artifact_id" => "work_graph:1",
          "input_subject_kind" => "plan_revision",
          "input_subject_id" => "plan-1",
          "role" => "semantic",
          "invalidation_policy" => "invalidate_on_change"
        },
        %{
          "consumer_artifact_id" => "agent_brief:SLC-A",
          "input_subject_kind" => "repo_inventory",
          "input_subject_id" => "repo-1",
          "role" => "advisory",
          "invalidation_policy" => "warn_on_change"
        }
      ]
    }

    preview =
      StructuralDryRun.preview_impact(
        index,
        [%{subject_kind: "plan_revision", subject_id: "plan-1"}],
        confidence: 0.4
      )

    assert preview.status == :fail_wide
    assert preview.confidence == 0.4
    assert preview.affected_artifact_ids == ["agent_brief:SLC-A", "work_graph:1"]
    assert preview.reason == :low_confidence
  end

  test "terminates with a residual wave when the work graph contains a cycle" do
    result =
      StructuralDryRun.run(%{
        slices: [%{stable_key: "A"}, %{stable_key: "B"}],
        work_edges: [
          %{from: "A", to: "B", kind: :execution_hard},
          %{from: "B", to: "A", kind: :execution_hard}
        ]
      })

    # Must return (not hang); cyclic nodes are emitted as a terminal residual wave.
    assert result.status == :ok
    assert result.waves == [["A", "B"]]
  end

  test "does not crash on an edge whose target is not a known slice" do
    result =
      StructuralDryRun.run(%{
        slices: [%{stable_key: "A"}],
        work_edges: [%{from: "A", to: "GHOST", kind: :execution_hard}]
      })

    assert result.status == :ok
    assert result.waves == [["A"]]
  end
end
