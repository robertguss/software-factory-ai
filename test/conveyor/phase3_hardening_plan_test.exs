defmodule Conveyor.Phase3HardeningPlanTest do
  use ExUnit.Case, async: true

  @plan_path "docs/phase-2/p2-b8/phase3-hardening-plan.md"

  @readiness_dimensions [
    "Evidence/gate integrity",
    "Grant scope/stability",
    "Contract stability",
    "Adapter reliability",
    "Operator clarity",
    "Serial execution",
    "Economics/latency",
    "Operational controls"
  ]

  test "hardening plan uses the Phase-3 readiness matrix and withholds entry contract" do
    plan = File.read!(@plan_path)

    for dimension <- @readiness_dimensions do
      assert plan =~ dimension
    end

    for branch <- [
          "harden_gate_first",
          "harden_adapter_first",
          "harden_contract_pipeline_first",
          "harden_operator_surface_first",
          "harden_evidence_kernel_first"
        ] do
      assert plan =~ branch
    end

    assert plan =~ "Recorded outcome: harden_gate_first"
    assert plan =~ "No Phase-3 entry contract is issued"
    assert plan =~ "first_pass_gate_success"
    assert plan =~ "material_dispute_rate"
    assert plan =~ "db_backed_mix_test_unavailable"
  end
end
