defmodule Conveyor.EmergencyStopTest do
  use ExUnit.Case, async: true

  alias Conveyor.EmergencyStop

  @schema_path "docs/schemas/conveyor.emergency_stop_state@1.json"

  test "to_record/1 emits a schema-conformant record for an engaged project stop" do
    record =
      EmergencyStop.engage(:project, "project-1",
        actor: "operator",
        reason: "runaway spend",
        trace_id: "trace-1",
        now: ~U[2026-06-19 00:00:00.000000Z]
      )
      |> EmergencyStop.to_record()

    assert record["schema_version"] == "conveyor.emergency_stop_state@1"
    assert record["scope"] == "project"
    assert record["project_id"] == "project-1"
    assert record["status"] == "engaged"
    assert record["actor"] == "operator"
    refute Map.has_key?(record, "scope_id")
    refute Map.has_key?(record, "cleared_by")
    assert_schema_valid!(record)
  end

  test "to_record/1 records the clearing operator in actor and conforms after clear" do
    record =
      EmergencyStop.engage(:project, "project-1",
        actor: "operator",
        reason: "runaway spend",
        trace_id: "trace-1",
        now: ~U[2026-06-19 00:00:00.000000Z]
      )
      |> EmergencyStop.clear(
        actor: "incident-commander",
        human_decision_id: "hd-1",
        now: ~U[2026-06-19 00:05:00.000000Z]
      )
      |> EmergencyStop.to_record()

    assert record["status"] == "clear"
    assert record["actor"] == "incident-commander"
    assert record["human_decision_id"] == "hd-1"
    refute Map.has_key?(record, "cleared_by")
    assert_schema_valid!(record)
  end

  test "to_record/1 omits project_id for a system-scoped stop" do
    record =
      EmergencyStop.engage(:system, "global",
        actor: "operator",
        reason: "global incident",
        trace_id: "trace-1",
        now: ~U[2026-06-19 00:00:00.000000Z]
      )
      |> EmergencyStop.to_record()

    assert record["scope"] == "system"
    refute Map.has_key?(record, "project_id")
    assert_schema_valid!(record)
  end

  defp assert_schema_valid!(record) do
    schema = @schema_path |> File.read!() |> Jason.decode!() |> JSV.build!()
    assert {:ok, _validated} = JSV.validate(record, schema)
  end
end
