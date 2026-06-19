defmodule Conveyor.ContractForgeAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-b1/acceptance-gate.md"

  @criteria [
    "every contract states current/desired/non-goal/scope/recovery",
    "public/cross-Slice interface ownership + compatibility are explicit",
    "internal implementation freedom is preserved",
    "machine ACs have a falsifying condition + seeds",
    "a scope addition requires approval",
    "every Slice explains why it is independently verifiable"
  ]

  test "P2-B1 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "AgentBriefContractSchemaTest",
          "ContractArchetypeTemplatesTest",
          "InterfacePolicyTest",
          "VerificationObligationDeriverTest",
          "FalsifierSeedDeriverTest",
          "ContractAuthorTest",
          "Conveyor.ContractForge.ContractAuthor",
          "Conveyor.ContractForge.InterfacePolicy"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
