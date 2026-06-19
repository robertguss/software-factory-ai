defmodule Conveyor.FailureDiagnosisTest do
  use ExUnit.Case, async: true

  alias Conveyor.FailureDiagnosis

  test "deterministic policy evidence produces immutable diagnosis before agent hypotheses" do
    context = %{
      subject: "run-attempt:policy-denied",
      policy_decisions: [
        %{result: :deny, reason: "network_egress_denied", evidence_ref: "policy-decision:1"}
      ],
      agent_hypotheses: ["implementation_bug"]
    }

    diagnosis = FailureDiagnosis.diagnose(context)
    same_diagnosis = FailureDiagnosis.diagnose(context)

    assert diagnosis["schema_version"] == "conveyor.failure_diagnosis@1"
    assert diagnosis["primary_classification"] == "policy_violation"
    assert diagnosis["contributing_factors"] == ["network_egress_denied"]
    assert diagnosis["observations"] == ["policy_decision:deny"]
    assert diagnosis["competing_hypotheses"] == ["implementation_bug"]
    assert diagnosis["confidence"] == 0.95
    assert diagnosis["confidence_basis"] == "deterministic_rule:policy_decision_denied"
    assert diagnosis["abstained"] == false
    assert diagnosis["evidence_refs"] == ["policy-decision:1"]
    assert diagnosis["diagnosis_digest"] == same_diagnosis["diagnosis_digest"]
  end

  test "insufficient deterministic evidence abstains as unknown" do
    diagnosis = FailureDiagnosis.diagnose(%{subject: "run-attempt:ambiguous"})

    assert diagnosis["primary_classification"] == "unknown"
    assert diagnosis["abstained"] == true
    assert diagnosis["confidence"] == 0.0
    assert diagnosis["confidence_basis"] == "deterministic_rules_abstained"
    assert diagnosis["observations"] == ["insufficient_structured_evidence"]
  end

  test "structured control-plane signals classify before agent hypotheses" do
    cases = [
      {%{emergency_stop: %{active: true, evidence_ref: "stop:1"}}, "emergency_stopped"},
      {%{budgets: [%{status: :exhausted, evidence_ref: "budget:1"}]}, "budget_exhausted"},
      {%{replay: %{status: :stale, evidence_ref: "cassette:1"}}, "cassette_stale"}
    ]

    for {structured_signal, expected_classification} <- cases do
      diagnosis =
        structured_signal
        |> Map.put(:subject, "run-attempt:control-plane")
        |> Map.put(:agent_hypotheses, ["implementation_bug"])
        |> FailureDiagnosis.diagnose()

      assert diagnosis["primary_classification"] == expected_classification
      assert diagnosis["abstained"] == false
      assert diagnosis["competing_hypotheses"] == ["implementation_bug"]
    end
  end
end
