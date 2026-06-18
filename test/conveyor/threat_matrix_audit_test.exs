defmodule Conveyor.ThreatMatrixAuditTest do
  use ExUnit.Case, async: true

  alias Conveyor.ThreatMatrixAudit

  @expected_threat_ids [
    "malicious_repository_content",
    "malicious_tool_output",
    "agent_policy_evasion",
    "test_weakening",
    "secret_exposure",
    "supply_chain_drift",
    "artifact_tampering",
    "reviewer_rubber_stamp",
    "gate_false_negative",
    "internal_state_corruption",
    "host_escape_or_overreach"
  ]

  test "maps every section 12 threat class to at least one existing check" do
    audit = ThreatMatrixAudit.audit()

    assert audit["schema_version"] == "conveyor.threat_matrix_audit@1"
    assert audit["passed"] == true
    assert audit["threat_count"] == 11
    assert ThreatMatrixAudit.threat_ids() == @expected_threat_ids

    for threat <- audit["threats"] do
      assert threat["covered"], "#{threat["id"]} has no coverage"
      assert threat["coverage"] != []

      for coverage <- threat["coverage"] do
        assert coverage["kind"] in ["test", "canary", "doctor"]

        assert File.exists?(coverage["path"]),
               "#{threat["id"]} references missing #{coverage["path"]}"
      end
    end
  end
end
