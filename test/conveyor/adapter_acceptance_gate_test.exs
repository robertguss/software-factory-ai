defmodule Conveyor.AdapterAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-1.5/p15-b2/acceptance-gate.md"

  @criteria [
    "conductor independently captures PatchSet/effects/verdict",
    "malformed/missing events fail closed",
    "requested autonomy is no higher than actual capability",
    "MockDegraded hits all mismatch branches",
    "provider/vendor code does not fork the conductor state machine",
    "open circuit blocks new attempts and affects grants"
  ]

  test "P15-B2 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "AgentRunnerDispatchTest",
          "AgentRunnerPiTest",
          "AgentRunnerMockDegradedTest",
          "AdapterConformanceFixturesTest",
          "AgentRunnerCapabilityPolicyTest",
          "AdapterHealthIntegrationTest"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
