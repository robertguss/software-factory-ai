defmodule Conveyor.Recovery.HonestyEvalTest do
  use ExUnit.Case, async: true

  alias Conveyor.Recovery.HonestyEval

  test "reports diagnosis precision recall coverage and abstention appropriateness" do
    report =
      HonestyEval.evaluate([
        %{
          case_id: "infra-hit",
          expected_classification: "infra_failure",
          predicted_classification: "infra_failure",
          abstained: false
        },
        %{
          case_id: "policy-missed",
          expected_classification: "policy_violation",
          predicted_classification: "infra_failure",
          abstained: false
        },
        %{
          case_id: "ambiguity-trap",
          expected_classification: "unknown",
          ambiguity_trap: true,
          abstained: true
        }
      ])

    assert report["schema_version"] == "conveyor.diagnosis_recovery_honesty_eval@1"
    assert report["case_count"] == 3
    assert report["coverage"] == 2 / 3
    assert report["abstention_rate"] == 1 / 3
    assert report["abstention_appropriateness"] == 1.0

    assert report["per_class"]["infra_failure"] == %{
             "true_positive" => 1,
             "false_positive" => 1,
             "false_negative" => 0,
             "precision" => 0.5,
             "recall" => 1.0
           }

    assert report["per_class"]["policy_violation"] == %{
             "true_positive" => 0,
             "false_positive" => 0,
             "false_negative" => 1,
             "precision" => nil,
             "recall" => 0.0
           }
  end

  test "reports recovery harm reconciliation and invalidation accuracy" do
    report =
      HonestyEval.evaluate([
        %{
          case_id: "safe-recovery",
          expected_classification: "cassette_stale",
          predicted_classification: "cassette_stale",
          abstained: false,
          harmful_action: false,
          recovery_succeeded: true,
          idempotent: true,
          expected_reconciliation: "reconciled",
          actual_reconciliation: "reconciled",
          expected_invalidated_refs: ["cassette:old"],
          predicted_invalidated_refs: ["cassette:old"]
        },
        %{
          case_id: "bad-recovery",
          expected_classification: "policy_violation",
          predicted_classification: "policy_violation",
          abstained: false,
          harmful_action: true,
          recovery_succeeded: false,
          idempotent: false,
          expected_reconciliation: "unresolved",
          actual_reconciliation: "reconciled",
          expected_invalidated_refs: ["policy-decision:deny"],
          predicted_invalidated_refs: ["context-pack:old"]
        }
      ])

    assert report["harmful_action_rate"] == 0.5
    assert report["recovery_success_rate"] == 0.5
    assert report["idempotency_rate"] == 0.5
    assert report["effect_reconciliation_correctness"] == 0.5
    assert report["invalidation_prediction_accuracy"] == 0.5
  end
end
