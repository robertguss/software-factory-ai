defmodule Conveyor.PlanningImpactPreviewTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.ImpactPreview

  test "summarizes deterministic operator impact across approvals contracts obligations and grants" do
    preview = ImpactPreview.build(sample_input(impact_confidence: 0.94))

    assert preview["schema_version"] == "conveyor.planning_impact_preview@1"
    assert preview["status"] == "selective"
    assert preview["new_snapshot_revision"] == "plan-revision-2"
    assert preview["invalidated_approvals"] == ["approval_root:checkout-epic"]
    assert preview["regenerated_contracts"] == ["contract:checkout"]
    assert preview["revalidated_obligations"] == ["verification_obligation:payments"]
    assert preview["new_run_specs"] == ["run_spec:checkout"]
    assert preview["grant_impact"] == [%{"grant_id" => "grant-1", "action" => "recheck_scope"}]
    assert preview["reusable_locks"] == ["lock:unchanged-admin"]
    assert preview["preview_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  test "fails wide when impact confidence is low" do
    preview = ImpactPreview.build(sample_input(impact_confidence: 0.42))

    assert preview["status"] == "low_confidence_fail_wide"
    assert preview["fail_wide"] == true
    assert "impact_confidence_low" in preview["operator_warnings"]
    assert "approval_root:checkout-epic" in preview["invalidated_approvals"]
    assert "contract:checkout" in preview["regenerated_contracts"]
    assert "verification_obligation:payments" in preview["revalidated_obligations"]
  end

  defp sample_input(overrides) do
    Map.merge(
      %{
        change_set_id: "changeset:payment-interface",
        changed_subjects: [%{subject_kind: "interface_contract", subject_id: "payments-api"}],
        next_revision_id: "plan-revision-2",
        new_run_specs: ["run_spec:checkout"],
        reusable_locks: ["lock:unchanged-admin"],
        grant_impacts: [%{grant_id: "grant-1", action: "recheck_scope"}],
        artifact_inputs: [
          %{
            consumer_artifact_id: "contract:checkout",
            input_subject_kind: "interface_contract",
            input_subject_id: "payments-api",
            role: "semantic",
            invalidation_policy: "invalidate_on_change"
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
      },
      Map.new(overrides)
    )
  end
end
