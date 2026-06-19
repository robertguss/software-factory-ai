defmodule Conveyor.TrustQualificationAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-1.5/p15-b5/acceptance-gate.md"

  @criteria [
    "every trust tool catches its planted defect and passes its clean boundary",
    "behavior drift is detected; a genuine refactor passes",
    "result is `no_divergence_observed`, not a general proof",
    "one meta-canary miss blocks the affected grant",
    "release report includes all failed/excluded cases"
  ]

  test "P15-B5 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "GateCanaryFixturesTest",
          "TrustToolCanariesTest",
          "BehaviorOracleAdapterTest",
          "trust-tool-canaries.json",
          "clean-controls.json"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
