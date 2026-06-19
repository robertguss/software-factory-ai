defmodule Conveyor.PlanningPilotRetrospectiveTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PilotRetrospective

  test "produces Chronicle report with typed failure diagnosis and recovery by class" do
    report =
      PilotRetrospective.build(%{
        selected_slice_ids: ["slice:a", "slice:b"],
        final_selected_slice_ids: ["slice:a", "slice:b"],
        failures: [
          failure("slice:b", "compiler"),
          failure("slice:a", "context")
        ],
        manual_interventions: []
      })

    assert report["status"] == "retrospective_recorded"
    assert report["release_failure_reasons"] == []
    assert report["failure_class_counts"] == %{"compiler" => 1, "context" => 1}
    assert report["all_failures_have_typed_recovery"] == true
    assert report["chronicle_markdown"] =~ "## Compiler Failures"
    assert report["chronicle_markdown"] =~ "## Context Failures"
  end

  test "detects changed selected set and failed replacement after outcomes" do
    report =
      PilotRetrospective.build(%{
        selected_slice_ids: ["slice:a", "slice:b"],
        final_selected_slice_ids: ["slice:a", "slice:c"],
        failures: [failure("slice:b", "implementation")],
        replacement_attempts: [%{failed_slice_id: "slice:b", replacement_slice_id: "slice:c"}],
        manual_interventions: []
      })

    assert report["status"] == "release_failure"
    assert "selected_set_changed_after_outcomes" in report["release_failure_reasons"]
    assert "failed_selection_replaced" in report["release_failure_reasons"]
  end

  test "from-scratch manual contract rewrite is release failure not success" do
    report =
      PilotRetrospective.build(%{
        selected_slice_ids: ["slice:a"],
        final_selected_slice_ids: ["slice:a"],
        failures: [],
        manual_interventions: [
          %{
            intervention_kind: "contract_edit",
            reconstruction_kind: "from_scratch",
            counts_as_generated_success: true
          }
        ]
      })

    assert report["status"] == "release_failure"
    assert "from_scratch_manual_contract_rewrite" in report["release_failure_reasons"]
  end

  defp failure(slice_id, failure_class) do
    %{
      slice_id: slice_id,
      failure_class: failure_class,
      comparison_ref: "comparison:#{slice_id}",
      diagnosis_ref: "diagnosis:#{slice_id}",
      recovery_ref: "recovery:#{slice_id}"
    }
  end
end
