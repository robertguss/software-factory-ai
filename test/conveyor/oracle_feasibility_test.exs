defmodule Conveyor.OracleFeasibilityTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestArchitect.OracleFeasibility

  test "classifies fully automatable oracle paths" do
    result =
      OracleFeasibility.classify!(%{
        acceptance_ref: "AC-001",
        verification_obligation_ref: "VOB-001",
        machine_oracle: true,
        result_adapter: "Conveyor.TestResultAdapter.JUnit",
        deterministic_inputs: true,
        oracle_assertions: ["response.completed == true"]
      })

    assert result["schema_version"] == "conveyor.oracle_feasibility@1"
    assert result["classification"] == "automatable"
    assert result["route"] == "test_architect"
    assert result["autonomy_cap"] == "normal"
    assert result["required_evidence_kinds"] == ["candidate_result", "calibration"]
    assert result["findings"] == []
  end

  test "classifies partially automatable oracle paths without weakening evidence" do
    result =
      OracleFeasibility.classify!(%{
        acceptance_ref: "AC-002",
        verification_obligation_ref: "VOB-002",
        machine_oracle: true,
        result_adapter: "Conveyor.TestResultAdapter.JUnit",
        deterministic_inputs: true,
        oracle_assertions: ["response.status == 202"],
        human_observation_procedure: "Review generated summary for domain wording."
      })

    assert result["classification"] == "partially_automatable"
    assert result["route"] == "test_architect_with_human_observation"
    assert result["autonomy_cap"] == "supervised"
    assert "human_observation" in result["required_evidence_kinds"]
  end

  test "routes boundary_unclear to split or clarify instead of retrying the vague slice" do
    result =
      OracleFeasibility.classify!(%{
        acceptance_ref: "AC-003",
        verification_obligation_ref: "VOB-003",
        boundary_questions: ["What counts as a good recommendation?"],
        machine_oracle: true,
        result_adapter: "Conveyor.TestResultAdapter.JUnit",
        deterministic_inputs: true,
        oracle_assertions: ["recommendation != nil"]
      })

    assert result["classification"] == "boundary_unclear"
    assert result["route"] == "split_or_clarify"
    assert result["autonomy_cap"] == "blocked"
    assert [%{"rule_key" => "oracle_feasibility.boundary_unclear"}] = result["findings"]
  end

  test "not automatable requires human-observed evidence and caps autonomy" do
    result =
      OracleFeasibility.classify!(%{
        acceptance_ref: "AC-004",
        verification_obligation_ref: "VOB-004",
        machine_oracle: false,
        human_observation_procedure: "Human reviewer compares UX tone against brand rubric."
      })

    assert result["classification"] == "not_automatable"
    assert result["route"] == "human_verification"
    assert result["autonomy_cap"] == "observe_only"
    assert result["required_evidence_kinds"] == ["human_observation"]
  end
end
