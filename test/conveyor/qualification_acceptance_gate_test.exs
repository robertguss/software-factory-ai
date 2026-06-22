defmodule Conveyor.QualificationAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "test/fixtures/phase-1.5/p15-b8/acceptance-gate.md"

  @criteria [
    "requested scope is machine-readable and compared with the issued scope",
    "no failed case/sample is omitted",
    "every waiver has owner/expiry/control/autonomy effect",
    "the grant is bound to adapter/profile/archetype/environment/policy/verification",
    "a broader requested scope fails if only a narrow grant is supported",
    "`qualification_gate` is reproducible from immutable evidence"
  ]

  test "P15-B8 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "QualificationGateTest",
          "QualificationGrantsTest",
          "QualificationReportTest",
          "QualificationBundleTest",
          "ConveyorQualificationGateTest",
          "ConveyorQualificationBundleTest",
          "QualificationPhaseNextDecisionTest"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
