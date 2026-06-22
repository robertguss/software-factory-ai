defmodule Conveyor.PlanningStaticCompilerAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-2/p2-a4/acceptance-gate.md"

  @criteria [
    "acyclicity/stable-identity/traceability/scope-provenance/interface-consistency/atomicity/invalidation/digest-separation properties pass",
    "pass cache + derivation impact tests pass",
    "all hard structural blockers clear",
    "no ContractLock/approval/implementation authority is created",
    "`compiler_structure_gate` passes",
    "no-agent lint runs without a QualificationGrant and produces the same deterministic diagnostics as the full compiler",
    "SARIF and static Markdown are projections of the same canonical findings"
  ]

  test "P2-A4 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "PlanningStaticDecisionPackageTest",
          "PlanningPromptDryCompileTest",
          "PlanningCompilerPropertiesTest",
          "PlanningStaticReportTest",
          "Mix.Tasks.ConveyorCompilerStructureGateTest",
          "PlanningPlanLintTest",
          "Mix.Tasks.ConveyorPlanLintTest",
          "Conveyor.Planning.CompilerStructureGate",
          "Conveyor.Planning.PlanLint"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
