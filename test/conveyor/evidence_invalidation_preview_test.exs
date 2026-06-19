defmodule Conveyor.Evidence.InvalidationPreviewTest do
  use ExUnit.Case, async: true

  alias Conveyor.Evidence.InvalidationPreview

  test "previews selective invalidation from derivation and authority indexes" do
    preview =
      InvalidationPreview.preview_invalidation(%{
        change_set_id: "changeset:payment-interface",
        impact_confidence: 0.94,
        changed_subjects: [
          %{subject_kind: "interface_contract", subject_id: "payments-api"}
        ],
        artifact_inputs: [
          %{
            consumer_artifact_id: "contract:checkout",
            input_subject_kind: "interface_contract",
            input_subject_id: "payments-api",
            role: "semantic",
            invalidation_policy: "invalidate_on_change"
          }
        ],
        interface_bindings: [
          %{
            interface_id: "payments-api",
            consumer_artifact_id: "run_prompt:checkout"
          }
        ],
        decision_blocks: [
          %{
            decision_block_id: "decision_block:payment-auth",
            subject_kind: "interface_contract",
            subject_id: "payments-api"
          }
        ],
        verification_obligations: [
          %{
            id: "verification_obligation:payments",
            subject_kind: "interface_contract",
            subject_id: "payments-api"
          }
        ],
        approval_roots: [
          %{
            root_id: "approval_root:checkout-epic",
            root_kind: "epic_authority",
            subject_kind: "interface_contract",
            subject_id: "payments-api"
          }
        ]
      })

    assert preview["schema_version"] == "conveyor.invalidation_preview@1"
    assert preview["change_set_id"] == "changeset:payment-interface"
    assert preview["impact_confidence"] == 0.94
    assert preview["confidence_status"] == "selective"
    assert preview["fail_wide"] == false

    assert preview["affected_subjects"] == [
             %{
               "subject_ref" => "approval_root:checkout-epic",
               "action" => "reapprove_epic",
               "reason" => "approval_root_changed"
             },
             %{
               "subject_ref" => "contract:checkout",
               "action" => "regenerate_contract",
               "reason" => "artifact_input_changed"
             },
             %{
               "subject_ref" => "decision_block:payment-auth",
               "action" => "regenerate_claims",
               "reason" => "decision_block_changed"
             },
             %{
               "subject_ref" => "run_prompt:checkout",
               "action" => "recompile_prompt",
               "reason" => "interface_binding_changed"
             },
             %{
               "subject_ref" => "verification_obligation:payments",
               "action" => "regenerate_verification_obligations",
               "reason" => "verification_obligation_changed"
             }
           ]
  end

  test "fails wide across known indexes when impact confidence is low" do
    preview =
      InvalidationPreview.preview_invalidation(%{
        change_set_id: "changeset:uncertain-policy",
        impact_confidence: 0.42,
        changed_subjects: [
          %{subject_kind: "policy_bundle", subject_id: "policy-main"}
        ],
        artifact_inputs: [
          %{
            consumer_artifact_id: "contract:checkout",
            input_subject_kind: "interface_contract",
            input_subject_id: "payments-api",
            role: "semantic",
            invalidation_policy: "invalidate_on_change"
          },
          %{
            consumer_artifact_id: "test_pack:checkout",
            input_subject_kind: "acceptance_criteria",
            input_subject_id: "checkout",
            role: "evidence",
            invalidation_policy: "invalidate_on_change"
          }
        ],
        interface_bindings: [
          %{interface_id: "payments-api", consumer_artifact_id: "run_prompt:checkout"}
        ],
        decision_blocks: [
          %{decision_block_id: "decision_block:payment-auth"}
        ],
        verification_obligations: [
          %{id: "verification_obligation:payments"}
        ],
        approval_roots: [
          %{root_id: "approval_root:shared", root_kind: "shared_authority"}
        ]
      })

    assert preview["confidence_status"] == "low_confidence_fail_wide"
    assert preview["fail_wide"] == true

    assert preview["affected_subjects"] == [
             %{
               "subject_ref" => "approval_root:shared",
               "action" => "reapprove_shared_root",
               "reason" => "impact_confidence_low"
             },
             %{
               "subject_ref" => "contract:checkout",
               "action" => "regenerate_contract",
               "reason" => "impact_confidence_low"
             },
             %{
               "subject_ref" => "decision_block:payment-auth",
               "action" => "regenerate_claims",
               "reason" => "impact_confidence_low"
             },
             %{
               "subject_ref" => "run_prompt:checkout",
               "action" => "recompile_prompt",
               "reason" => "impact_confidence_low"
             },
             %{
               "subject_ref" => "test_pack:checkout",
               "action" => "revalidate_only",
               "reason" => "impact_confidence_low"
             },
             %{
               "subject_ref" => "verification_obligation:payments",
               "action" => "regenerate_verification_obligations",
               "reason" => "impact_confidence_low"
             }
           ]
  end

  test "review-only presentation changes do not invalidate authority roots" do
    preview =
      InvalidationPreview.preview_invalidation(%{
        change_set_id: "changeset:review-erratum",
        impact_confidence: 0.94,
        changed_subjects: [
          %{subject_kind: "rendered_review", subject_id: "review-typo"}
        ],
        artifact_inputs: [
          %{
            consumer_artifact_id: "review:checkout",
            input_subject_kind: "rendered_review",
            input_subject_id: "review-typo",
            role: "presentation",
            invalidation_policy: "ignore_after_capture"
          }
        ],
        approval_roots: [
          %{
            root_id: "approval_root:checkout-epic",
            root_kind: "epic_authority",
            subject_kind: "interface_contract",
            subject_id: "payments-api"
          }
        ]
      })

    assert preview["confidence_status"] == "selective"
    assert preview["affected_subjects"] == []
  end
end
