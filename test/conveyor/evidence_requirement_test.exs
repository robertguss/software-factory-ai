defmodule Conveyor.EvidenceRequirementTest do
  use ExUnit.Case, async: true

  alias Conveyor.Verification

  @obligation_id "verification_obligation:sha256:abc"

  test "EvidenceRequirement evaluates every required dimension independently" do
    requirement =
      Verification.new_evidence_requirement!(%{
        verification_obligation_id: @obligation_id,
        required_dimensions: [:specification_present, :candidate_result, :hermeticity],
        created_at: "2026-06-19T00:00:00Z"
      })

    assert Verification.evidence_dimensions() ==
             ~w(specification_present base_calibration harness_validity candidate_result hermeticity repeatability adversarial_challenge mutation_assessment human_observation environment_freshness)

    assert requirement["schema_version"] == "conveyor.evidence_requirement@1"

    assert requirement["required_dimensions"] ==
             ~w(specification_present candidate_result hermeticity)

    assert requirement["dimension_predicates"]["hermeticity"] == %{
             "evidence_kind" => "hermeticity",
             "validity" => "valid"
           }

    evidence = [
      evidence("spec", :specification, :valid),
      evidence("candidate", :candidate_result, :valid),
      evidence("hermetic", :hermeticity, :valid)
    ]

    satisfaction =
      Verification.evaluate_requirement(requirement, evidence,
        policy_decision_id: "policy-decision:allow",
        evaluated_at: "2026-06-19T00:01:00Z"
      )

    assert satisfaction["schema_version"] == "conveyor.obligation_satisfaction@1"
    assert satisfaction["verification_obligation_id"] == @obligation_id
    assert satisfaction["evidence_requirement_digest"] == requirement["requirement_digest"]
    assert satisfaction["result"] == "satisfied"
    assert satisfaction["consumed_evidence_ids"] == Enum.map(evidence, & &1["id"])
    assert satisfaction["dimension_results"]["hermeticity"]["status"] == "satisfied"
  end

  test "required dimensions are not satisfied by a generic stronger-looking evidence stage" do
    requirement =
      Verification.new_evidence_requirement!(%{
        verification_obligation_id: @obligation_id,
        required_dimensions: [:hermeticity],
        created_at: "2026-06-19T00:00:00Z"
      })

    mutation_evidence = [evidence("mutation", :mutation_assessment, :valid)]

    satisfaction =
      Verification.evaluate_requirement(requirement, mutation_evidence,
        policy_decision_id: "policy-decision:block",
        evaluated_at: "2026-06-19T00:01:00Z"
      )

    assert satisfaction["result"] == "not_assessed"
    assert satisfaction["consumed_evidence_ids"] == []

    assert satisfaction["dimension_results"]["hermeticity"] == %{
             "status" => "missing",
             "required_evidence_kind" => "hermeticity",
             "evidence_ids" => []
           }
  end

  test "suspect invalid or expired required evidence blocks authority" do
    requirement =
      Verification.new_evidence_requirement!(%{
        verification_obligation_id: @obligation_id,
        required_dimensions: [:repeatability],
        created_at: "2026-06-19T00:00:00Z"
      })

    satisfaction =
      Verification.evaluate_requirement(
        requirement,
        [evidence("repeatability", :repeatability, :suspect)],
        policy_decision_id: "policy-decision:block",
        evaluated_at: "2026-06-19T00:01:00Z"
      )

    assert satisfaction["result"] == "blocked"
    assert satisfaction["dimension_results"]["repeatability"]["status"] == "blocked"

    assert satisfaction["dimension_results"]["repeatability"]["blocking_validities"] == [
             "suspect"
           ]
  end

  test "active waiver produces an explicit waived satisfaction instead of valid evidence" do
    requirement =
      Verification.new_evidence_requirement!(%{
        verification_obligation_id: @obligation_id,
        required_dimensions: [:environment_freshness],
        created_at: "2026-06-19T00:00:00Z"
      })

    waiver =
      Verification.new_waiver!(%{
        verification_obligation_id: @obligation_id,
        human_decision_id: "human-decision:waive-1",
        reason: "Temporary environment probe outage.",
        compensating_control_refs: ["control:manual-env-check"],
        max_autonomy: "observe_only",
        owner: "principal-engineer",
        expires_at: "2026-06-26T00:00:00Z",
        status: :active
      })

    satisfaction =
      Verification.evaluate_requirement(requirement, [],
        policy_decision_id: "policy-decision:waive",
        waiver: waiver,
        evaluated_at: "2026-06-19T00:01:00Z"
      )

    assert satisfaction["result"] == "waived"
    assert satisfaction["waiver_id"] == waiver["id"]
    assert satisfaction["consumed_evidence_ids"] == []
    assert satisfaction["dimension_results"]["environment_freshness"]["status"] == "waived"
  end

  defp evidence(label, kind, validity) do
    Verification.new_evidence!(%{
      verification_obligation_id: @obligation_id,
      producer_kind: "test_pack",
      producer_ref: "test-pack:#{label}",
      evidence_kind: kind,
      validity: validity,
      result_ref: "artifact:#{label}",
      evidence_digest: "sha256:#{label}",
      created_at: "2026-06-19T00:00:00Z"
    })
  end
end
