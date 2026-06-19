defmodule Conveyor.CassetteAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-1.5/p15-b3/acceptance-gate.md"

  @criteria [
    "repeated live samples create separate recordings",
    "generation-surface changes miss every replay mode",
    "gate/test/evaluation-only changes remain eligible for hybrid replay",
    "strict replay rejects different tool args/order",
    "full replay reproduces the conductor projection",
    "hybrid replay reruns current gates/obligations",
    "compatible replay never satisfies a trust gate",
    "anchor selection is frozen before the evaluated change",
    "recorded gate claims never become authority"
  ]

  test "P15-B3 acceptance gate documents every exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "CassettesTest",
          "CassetteCausalTranscriptTest",
          "CassetteReplayEngineTest",
          "CassetteNondeterminismTest",
          "CassetteFreshnessTest",
          "CassetteReplayDiagnosticsTest",
          "CassetteReplayAnchorSetTest",
          "EvidenceKernelResourcesTest"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
