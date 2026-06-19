defmodule Conveyor.EvidenceKernelDogfoodTest do
  use ExUnit.Case, async: true

  @route_path "docs/phase-1.5/p15-a5/tracer-kernel-route.json"
  @report_path "docs/phase-1.5/p15-a5/static-evidence-report.md"
  @audit_path "docs/phase-1.5/p15-a5/no-bypass-audit.json"

  @required_paths ~w(
    PolicyDecision
    ToolContract
    RoleView
    StationFencing
    EffectReceipt
    AuthorityEvent
    ArtifactStore
    EmergencyStop
    BudgetReservation
    Retention
  )

  test "Phase-1 tracer route exercises every evidence-kernel path" do
    route = @route_path |> File.read!() |> Jason.decode!()

    assert route["schema_version"] == "conveyor.tracer_kernel_route@1"
    assert route["phase_1_behavior_changed"] == false
    assert Enum.map(route["kernel_paths"], & &1["key"]) == @required_paths
    assert Enum.all?(route["kernel_paths"], &(&1["status"] == "adopted"))
  end

  test "static evidence report and no-bypass audit are present" do
    report = File.read!(@report_path)
    audit = @audit_path |> File.read!() |> Jason.decode!()

    assert report =~ "Kernel Adoption"
    assert report =~ "Migration Notes"
    assert audit["schema_version"] == "conveyor.no_bypass_audit@1"
    assert audit["verdict"] == "pass"
    assert audit["bypasses"] == []
  end
end
