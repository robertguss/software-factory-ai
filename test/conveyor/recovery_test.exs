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

  test "safe automatic actions require deterministic fenced grant and budget evidence" do
    proposal =
      Recovery.new_proposal!(%{
        failure_diagnosis_id: "failure-diagnosis:projection",
        action_key: :rebuild_stale_projection,
        arguments_ref: "artifact://recovery/rebuild-projection.json",
        reusable_artifact_refs: ["run-bundle:1"],
        invalidated_artifact_refs: ["projection:old"],
        requires_human: false
      })

    decision =
      Recovery.safe_auto_action_decision(proposal, %{
        deterministic_precondition: true,
        current_fence: true,
        active_grant: true,
        budget_reserved: true,
        bounded_retry: true
      })

    assert decision["decision"] == "auto_applicable"
    assert decision["auto_apply"] == true
    assert decision["requires_human"] == false
    assert decision["failed_criteria"] == []

    assert decision["satisfied_criteria"] == [
             "deterministic_precondition",
             "current_fence",
             "active_grant",
             "budget_reserved",
             "idempotent",
             "bounded_retry"
           ]
  end

  test "semantic recovery remains human gated even with safe operational criteria" do
    proposal =
      Recovery.new_proposal!(%{
        failure_diagnosis_id: "failure-diagnosis:contract",
        action_key: :retry_with_fresh_permit,
        arguments_ref: "artifact://recovery/amend-contract.json",
        reusable_artifact_refs: ["contract-lock:1"],
        invalidated_artifact_refs: ["planning-spec:old"],
        requires_new_spec: true,
        requires_human: false
      })

    decision =
      Recovery.safe_auto_action_decision(proposal, %{
        deterministic_precondition: true,
        current_fence: true,
        active_grant: true,
        budget_reserved: true,
        bounded_retry: true
      })

    assert decision["decision"] == "human_required"
    assert decision["auto_apply"] == false
    assert decision["requires_human"] == true
    assert decision["human_gated_reasons"] == ["requires_new_spec"]
  end
end
