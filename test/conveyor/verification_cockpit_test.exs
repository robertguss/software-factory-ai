defmodule Conveyor.VerificationCockpitTest do
  use ExUnit.Case, async: true

  alias Conveyor.Verification
  alias Conveyor.Verification.Cockpit

  @blocked_obligation_id "verification_obligation:sha256:blocked"
  @satisfied_obligation_id "verification_obligation:sha256:satisfied"

  test "projection summarizes obligation coverage invalid evidence and active waivers" do
    blocked_obligation = obligation(@blocked_obligation_id, "AC-001", :property)
    satisfied_obligation = obligation(@satisfied_obligation_id, "AC-002", :example)

    invalid_evidence =
      evidence(@blocked_obligation_id, "bad-repeatability", :repeatability, :invalid)

    valid_evidence = evidence(@satisfied_obligation_id, "candidate", :candidate_result, :valid)

    blocked_satisfaction =
      satisfaction(@blocked_obligation_id, "blocked", [invalid_evidence["id"]])

    satisfied_satisfaction =
      satisfaction(@satisfied_obligation_id, "satisfied", [valid_evidence["id"]])

    waiver =
      Verification.new_waiver!(%{
        verification_obligation_id: @blocked_obligation_id,
        human_decision_id: "human-decision:waive-1",
        reason: "Temporary repeatability lab outage.",
        compensating_control_refs: ["control:manual-review"],
        max_autonomy: "observe_only",
        owner: "principal-engineer",
        expires_at: "2026-06-26T00:00:00Z",
        status: :active
      })

    projection =
      Cockpit.project(
        %{
          obligations: [blocked_obligation, satisfied_obligation],
          evidence: [invalid_evidence, valid_evidence],
          satisfactions: [blocked_satisfaction, satisfied_satisfaction],
          waivers: [waiver],
          quarantines: []
        },
        generated_at: "2026-06-19T00:00:00Z"
      )

    assert projection["schema_version"] == "conveyor.verification_cockpit_projection@1"

    assert projection["summary"] == %{
             "required_obligations" => 2,
             "satisfied" => 1,
             "blocked" => 1,
             "waived" => 0,
             "not_assessed" => 0,
             "invalid_evidence" => 1,
             "active_waivers" => 1
           }

    blocked = Enum.find(projection["obligations"], &(&1["id"] == @blocked_obligation_id))

    assert blocked["satisfaction_result"] == "blocked"
    assert blocked["invalid_evidence_ids"] == [invalid_evidence["id"]]
    assert blocked["waiver"]["owner"] == "principal-engineer"
    assert blocked["waiver"]["expires_at"] == "2026-06-26T00:00:00Z"
    assert blocked["safe_next_action"] == "replace_invalid_evidence_or_review_active_waiver"
  end

  test "projection exposes quarantines without converting them into satisfaction" do
    obligation = obligation(@blocked_obligation_id, "AC-001", :property)
    valid_evidence = evidence(@blocked_obligation_id, "candidate", :candidate_result, :valid)

    quarantine =
      Verification.new_quarantine!(%{
        test_pack_id: "test-pack:unit",
        test_id: "test:flaky",
        reason: :flaky,
        required_for_obligation_ids: [@blocked_obligation_id],
        status: :quarantined,
        excluded_from: :both,
        evidence_ref: valid_evidence["id"],
        created_at: "2026-06-19T00:00:00Z"
      })

    projection =
      Cockpit.project(
        %{
          obligations: [obligation],
          evidence: [valid_evidence],
          satisfactions: [satisfaction(@blocked_obligation_id, "blocked", [valid_evidence["id"]])],
          waivers: [],
          quarantines: [quarantine]
        },
        generated_at: "2026-06-19T00:00:00Z"
      )

    [row] = projection["obligations"]

    assert row["satisfaction_result"] == "blocked"
    assert row["quarantine_ids"] == [quarantine["id"]]
    assert row["safe_next_action"] == "replace_quarantined_evidence_or_request_waiver"
  end

  defp obligation(id, acceptance_ref, kind) do
    %{
      "schema_version" => "conveyor.verification_obligation@1",
      "id" => id,
      "slice_id" => "slice-1",
      "acceptance_ref" => acceptance_ref,
      "obligation_kind" => Atom.to_string(kind),
      "required" => true,
      "oracle_definition_ref" => "oracle:#{acceptance_ref}",
      "evidence_requirement_ref" => "requirement:#{acceptance_ref}",
      "status" => "open"
    }
  end

  defp evidence(obligation_id, label, kind, validity) do
    Verification.new_evidence!(%{
      verification_obligation_id: obligation_id,
      producer_kind: "test_pack",
      producer_ref: "test-pack:#{label}",
      evidence_kind: kind,
      validity: validity,
      result_ref: "artifact:#{label}",
      evidence_digest: "sha256:#{label}",
      created_at: "2026-06-19T00:00:00Z"
    })
  end

  defp satisfaction(obligation_id, result, consumed_evidence_ids) do
    %{
      "verification_obligation_id" => obligation_id,
      "evidence_requirement_digest" => "sha256:requirement",
      "consumed_evidence_ids" => consumed_evidence_ids,
      "dimension_results" => %{},
      "result" => result,
      "policy_decision_id" => "policy-decision:#{result}",
      "satisfaction_digest" => "sha256:satisfaction-#{result}",
      "evaluated_at" => "2026-06-19T00:00:00Z"
    }
  end
end
