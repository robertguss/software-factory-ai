defmodule Conveyor.PlanningAmendmentEnforcementTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.AmendmentEnforcement

  @manual_schema_path "docs/schemas/conveyor.manual_intervention_artifact@1.json"

  test "material contract faults terminate the old attempt and create a new authority chain without consuming retry budget" do
    plan =
      AmendmentEnforcement.plan(%{
        materiality: "material",
        fault_class: "contract_fault",
        base_attempt_id: "run-attempt:checkout:r4:a1",
        resulting_plan_revision_id: "plan-revision:checkout:r5",
        retry_budget_remaining: 2
      })

    assert plan["status"] == "new_attempt_required"
    assert plan["terminated_attempt_id"] == "run-attempt:checkout:r4:a1"
    assert plan["retry_budget_effect"] == "not_consumed_contract_fault"
    assert plan["retry_budget_remaining"] == 2
    assert plan["prior_attempt_reused"] == false

    assert created_ref("authority_root", "authority-root:plan-revision:checkout:r5") in plan[
             "created_refs"
           ]

    assert created_ref("contract_lock", "contract-lock:plan-revision:checkout:r5") in plan[
             "created_refs"
           ]

    assert created_ref("run_spec", "run-spec:plan-revision:checkout:r5") in plan["created_refs"]

    assert created_ref("run_attempt", "run-attempt:plan-revision:checkout:r5") in plan[
             "created_refs"
           ]
  end

  test "typed manual intervention artifacts are schema-valid and require reapproval for material edits" do
    artifact =
      AmendmentEnforcement.manual_intervention_artifact(%{
        intervention_kind: "contract_edit",
        subject_ref: resource_ref("contract_lock", "contract-lock:checkout:r4"),
        content_ref: resource_ref("source_anchor", "manual-edit:checkout:r5"),
        actor_action_id: "actor-action:operator:manual-contract-edit",
        reason:
          "Manual edit records a material contract correction without counting it as generated success.",
        affected_refs: [resource_ref("run_spec", "run-spec:checkout:r4")],
        materiality_labels: ["material", "acceptance_criteria"],
        created_at: "2026-06-19T11:30:00Z"
      })

    assert artifact["counts_as_generated_success"] == false
    assert artifact["requires_reapproval"] == true
    assert_schema_valid!(artifact)
  end

  test "hidden manual reconstruction remains a release failure" do
    verdict =
      AmendmentEnforcement.manual_intervention_verdict(%{
        manual_reconstruction_detected: true,
        manual_intervention_artifact: nil
      })

    assert verdict["status"] == "release_failure"
    assert verdict["reason"] == "hidden_manual_reconstruction"
  end

  defp assert_schema_valid!(resource) do
    schema =
      @manual_schema_path
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(resource, schema)
  end

  defp created_ref(kind, id), do: resource_ref(kind, id)

  defp resource_ref(kind, id) do
    %{"schema_version" => "conveyor.resource_ref@1", "kind" => kind, "id_or_key" => id}
  end
end
