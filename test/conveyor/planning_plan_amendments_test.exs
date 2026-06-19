defmodule Conveyor.PlanningPlanAmendmentsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanAmendments

  @schema_path "docs/schemas/conveyor.plan_amendment_proposal@1.json"

  test "builds PlanAmendmentProposal with affected downstream approvals obligations epics and grants" do
    proposal = PlanAmendments.propose(sample_input(materiality: "material"))

    assert proposal["schema_version"] == "conveyor.plan_amendment_proposal@1"
    assert proposal["plan_id"] == "plan:contract-foundry-pilot"
    assert proposal["base_plan_revision_id"] == "plan-revision:contract-foundry-pilot:r4"
    assert proposal["dispute_kind"] == "material_change"
    assert proposal["materiality"] == "material"
    assert proposal["status"] == "human_review_required"

    assert ref("interface_contract", "payments-api") in proposal["affected_refs"]
    assert ref("epic", "checkout") in proposal["affected_refs"]

    assert ref("qualification_grant", "grant:qualified-contract-foundry") in proposal[
             "affected_refs"
           ]

    assert ref("contract", "checkout") in proposal["downstream_refs"]
    assert ref("run_prompt", "checkout") in proposal["downstream_refs"]
    assert ref("verification_obligation", "payments") in proposal["downstream_refs"]
    assert ref("approval_root", "checkout-epic") in proposal["downstream_refs"]

    assert ref("contract", "checkout") in proposal["invalidated_artifact_refs"]
    assert ref("run_prompt", "checkout") in proposal["invalidated_artifact_refs"]
    assert proposal["impact_preview_ref"]["kind"] == "planning_impact_preview"
    assert proposal["impact_preview_ref"]["digest"]["value"] =~ ~r/^[0-9a-f]{64}$/

    assert_schema_valid!(proposal)
  end

  test "nonmaterial clarification can be recorded without invalidating reusable artifacts" do
    proposal =
      PlanAmendments.propose(
        sample_input(
          dispute_kind: "nonmaterial_correction",
          materiality: "nonmaterial",
          changed_subjects: [%{subject_kind: "rendered_review", subject_id: "review-typo"}],
          artifact_inputs: [
            %{
              consumer_artifact_id: "review:checkout",
              input_subject_kind: "rendered_review",
              input_subject_id: "review-typo",
              role: "presentation",
              invalidation_policy: "ignore_after_capture"
            }
          ],
          interface_bindings: [],
          verification_obligations: [],
          approval_roots: [],
          grant_impacts: []
        )
      )

    assert proposal["status"] == "accepted"
    assert proposal["affected_refs"] == [ref("rendered_review", "review-typo")]
    assert proposal["downstream_refs"] == []
    assert proposal["invalidated_artifact_refs"] == []
    assert_schema_valid!(proposal)
  end

  test "declared grant impacts surface in affected_refs even when there are no downstream refs" do
    proposal =
      PlanAmendments.propose(
        sample_input(
          dispute_kind: "nonmaterial_correction",
          materiality: "nonmaterial",
          changed_subjects: [%{subject_kind: "rendered_review", subject_id: "review-typo"}],
          artifact_inputs: [],
          interface_bindings: [],
          verification_obligations: [],
          approval_roots: [],
          grant_impacts: [%{grant_id: "grant:standalone", action: "recheck_scope"}]
        )
      )

    assert proposal["downstream_refs"] == []
    assert ref("qualification_grant", "grant:standalone") in proposal["affected_refs"]
  end

  defp assert_schema_valid!(resource) do
    schema =
      @schema_path
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(resource, schema)
  end

  defp sample_input(overrides) do
    Map.merge(
      %{
        plan_id: "plan:contract-foundry-pilot",
        base_plan_revision_id: "plan-revision:contract-foundry-pilot:r4",
        change_set_id: "change-set:payments-interface-v2",
        dispute_kind: "material_change",
        materiality: "material",
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
            invalidation_policy: "invalidate_on_change",
            epic_key: "checkout",
            grant_id: "grant:qualified-contract-foundry"
          }
        ],
        interface_bindings: [
          %{
            interface_id: "payments-api",
            consumer_artifact_id: "run_prompt:checkout",
            epic_key: "checkout"
          }
        ],
        verification_obligations: [
          %{
            id: "verification_obligation:payments",
            subject_kind: "interface_contract",
            subject_id: "payments-api",
            epic_key: "checkout"
          }
        ],
        approval_roots: [
          %{
            root_id: "approval_root:checkout-epic",
            root_kind: "epic_authority",
            subject_kind: "interface_contract",
            subject_id: "payments-api",
            epic_key: "checkout"
          }
        ],
        grant_impacts: [
          %{grant_id: "grant:qualified-contract-foundry", action: "recheck_scope"}
        ]
      },
      Map.new(overrides)
    )
  end

  defp ref(kind, id),
    do: %{"schema_version" => "conveyor.resource_ref@1", "kind" => kind, "id_or_key" => id}
end
