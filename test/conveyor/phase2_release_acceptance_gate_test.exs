defmodule Conveyor.Phase2ReleaseAcceptanceGateTest do
  use ExUnit.Case, async: true

  @gate_path "docs/phase-2/p2-b8/acceptance-gate.md"

  @criteria [
    "every hard correctness invariant passes",
    "the requested grant remains current for pilot/release scope",
    "all waivers are explicit/scoped/expiring/reflected in autonomy",
    "pre-registered pilot evidence is attached",
    "the §17.8 six/eight-dimension Phase-3 matrix is used",
    "roadmap pressure cannot hide a failed gate without visible human risk acceptance and no automatic authority"
  ]

  test "P2-B8 acceptance gate documents each exit criterion with evidence" do
    gate = File.read!(@gate_path)

    for criterion <- @criteria do
      assert gate =~ criterion
    end

    for evidence_ref <- [
          "release-suite-report.md",
          "quality-hypothesis-comparison.md",
          "release-record.md",
          "phase2-gate.json",
          "phase-next-decision.json",
          "phase3-hardening-plan.md",
          "phase2_gate failed",
          "No Phase-3 entry contract is issued",
          "db_backed_mix_test_unavailable"
        ] do
      assert gate =~ evidence_ref
    end
  end
end
