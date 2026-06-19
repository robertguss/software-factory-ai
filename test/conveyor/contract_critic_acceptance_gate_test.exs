defmodule Conveyor.ContractCriticAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-b3/acceptance-gate.md"

  @criteria [
    "planted loopholes/scope-laundering are caught",
    "disagreement is retained",
    "no repair weakens semantics without authority",
    "oscillation parks",
    "unaffected passes/artifacts are reused",
    "the Critic cannot approve/lock"
  ]

  test "P2-B3 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "ContractCriticLensesTest",
          "ContractCriticCheapestWrongTest",
          "ContractCriticIndependenceTest",
          "ContractCriticRepairLoopTest",
          "ContractCriticRepairDiffTest",
          "Conveyor.ContractCritic.Lenses",
          "Conveyor.ContractCritic.RepairLoop",
          "Conveyor.ContractCritic.RepairDiff"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
