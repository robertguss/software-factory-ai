defmodule Conveyor.EvidenceTimeMachineAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-1.5/p15-b6/acceptance-gate.md"

  @criteria [
    "weakening/freshness/root/grant changes classify materially",
    "missing/erased/tampered evidence yields `incomparable`",
    "the ambiguous fixture abstains",
    "diagnosis remains immutable",
    "semantic recovery requires normal authority",
    "safe actions are idempotent, fenced, budgeted, and grant-admitted",
    "raw shell commands are not authoritative recovery data"
  ]

  test "P15-B6 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "EvidenceComparatorTest",
          "ConveyorEvidenceTimeMachineTest",
          "FailureDiagnosisTest",
          "RecoveryTest",
          "Recovery.HonestyEvalTest",
          "InvalidationPreviewTest"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
