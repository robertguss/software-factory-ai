defmodule Conveyor.RecoveryTest do
  use ExUnit.Case, async: true

  alias Conveyor.Recovery

  test "builds registry-backed RecoveryProposal without raw shell authority" do
    proposal =
      Recovery.new_proposal!(%{
        failure_diagnosis_id: "failure-diagnosis:infra",
        action_key: :retry_with_fresh_permit,
        arguments_ref: "artifact://recovery/retry-args.json",
        reusable_artifact_refs: ["contract-lock:1", "test-pack:1"],
        invalidated_artifact_refs: ["permit:stale"],
        requires_human: false
      })

    same_proposal = Recovery.new_proposal!(proposal)

    assert proposal["schema_version"] == "conveyor.recovery_proposal@1"
    assert proposal["action_key"] == "retry_with_fresh_permit"
    assert proposal["requires_new_spec"] == false
    assert proposal["requires_new_attempt"] == true
    assert proposal["idempotent"] == true
    assert proposal["precondition_policy_key"] == "recovery.retry.fenced"
    assert proposal["proposal_digest"] == same_proposal["proposal_digest"]

    assert_raise ArgumentError, ~r/unknown recovery action_key/, fn ->
      Recovery.new_proposal!(%{proposal | "action_key" => "raw_shell"})
    end
  end

  test "authorizes RecoveryAction separately from proposal" do
    proposal =
      Recovery.new_proposal!(%{
        failure_diagnosis_id: "failure-diagnosis:projection",
        action_key: :rebuild_stale_projection,
        arguments_ref: "artifact://recovery/rebuild-projection.json",
        reusable_artifact_refs: ["run-bundle:1"],
        invalidated_artifact_refs: ["projection:old"],
        requires_human: false
      })

    action =
      Recovery.authorize_action!(proposal,
        authorized_by: "operator",
        authorization_ref: "policy-decision:allow-recovery",
        created_at: "2026-06-19T00:00:00Z"
      )

    assert action["schema_version"] == "conveyor.recovery_action@1"
    assert action["recovery_proposal_id"] == proposal["proposal_digest"]
    assert action["action_key"] == proposal["action_key"]
    assert action["authorized_by"] == "operator"
    assert action["status"] == "pending"
    assert action["idempotency_key"] =~ "recovery:"
  end
end
