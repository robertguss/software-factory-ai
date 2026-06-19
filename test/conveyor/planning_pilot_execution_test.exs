defmodule Conveyor.PlanningPilotExecutionTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PilotExecution

  test "summarizes serial selected slice execution and required pilot metrics" do
    report =
      PilotExecution.summarize(%{
        implementation_width: 1,
        selected_slice_ids: ["slice:a", "slice:b", "slice:c"],
        events: [
          event("slice:a", 1, "passed", "first_pass", []),
          event("slice:b", 2, "parked", "eventual_pending", ["context_miss", "missing_interface"]),
          event("slice:c", 3, "passed", "recovered", ["post_start_amendment", "human_edit"])
        ],
        incidents: [
          %{kind: "grant", severity: "warning"},
          %{kind: "budget", severity: "warning"}
        ],
        diagnosis_records: [
          %{slice_id: "slice:b", quality: "complete"},
          %{slice_id: "slice:c", quality: "complete"}
        ],
        recovery_records: [
          %{slice_id: "slice:c", quality: "complete"}
        ]
      })

    assert report["status"] == "serial_execution_recorded"
    assert report["implementation_width"] == 1
    assert report["serial_order"] == ["slice:a", "slice:b", "slice:c"]
    assert report["first_pass_gate_success_rate"] == 1 / 3
    assert report["eventual_gate_success_rate"] == 2 / 3
    assert report["clarification_or_dispute_rate"] == 1 / 3
    assert report["context_miss_count"] == 1
    assert report["missing_obligation_or_interface_count"] == 1
    assert report["post_start_amendment_count"] == 1
    assert report["human_edit_count"] == 1
    assert report["incident_counts"] == %{"budget" => 1, "grant" => 1}
    assert report["diagnosis_recovery_quality"] == "complete"
  end

  test "blocks non-serial execution width" do
    report =
      PilotExecution.summarize(%{
        implementation_width: 2,
        selected_slice_ids: ["slice:a"],
        events: [event("slice:a", 1, "passed", "first_pass", [])]
      })

    assert report["status"] == "blocked"
    assert "implementation_width_not_one" in report["blocking_reasons"]
  end

  defp event(slice_id, sequence, status, gate_result, findings) do
    %{
      slice_id: slice_id,
      sequence: sequence,
      status: status,
      gate_result: gate_result,
      findings: findings
    }
  end
end
