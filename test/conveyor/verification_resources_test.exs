defmodule Conveyor.VerificationResourcesTest do
  use ExUnit.Case, async: true

  alias Conveyor.Verification

  @obligation_attrs %{
    slice_id: "slice-1",
    acceptance_ref: "AC-001",
    obligation_kind: :property,
    required: true,
    oracle_definition_ref: "artifact:oracle/property-1",
    evidence_requirement_ref: "sha256:req",
    status: :open
  }

  test "VerificationObligation records the authority unit with constrained kind and status" do
    obligation = Verification.new_obligation!(@obligation_attrs)
    same_obligation = Verification.new_obligation!(@obligation_attrs)
    other_kind = Verification.new_obligation!(%{@obligation_attrs | obligation_kind: :example})

    assert Verification.obligation_kinds() ==
             ~w(example property interface differential metamorphic policy human_judgment)

    assert obligation["schema_version"] == "conveyor.verification_obligation@1"
    assert obligation["id"] == same_obligation["id"]
    assert obligation["id"] != other_kind["id"]
    assert obligation["obligation_kind"] == "property"
    assert obligation["required"] == true

    assert_raise ArgumentError, ~r/obligation_kind must be one of/, fn ->
      Verification.new_obligation!(%{@obligation_attrs | obligation_kind: :aggregate_test_pack})
    end
  end

  test "VerificationEvidence preserves ten evidence kinds and explicit validity" do
    evidence =
      Verification.new_evidence!(%{
        verification_obligation_id: "verification_obligation:sha256:abc",
        producer_kind: :test_pack,
        producer_ref: "test-pack:unit",
        evidence_kind: :candidate_result,
        validity: :valid,
        environment_fingerprint_digest: "sha256:env",
        result_ref: "artifact:test-result",
        evidence_digest: "sha256:evidence",
        created_at: "2026-06-19T00:00:00Z"
      })

    assert Verification.evidence_kinds() ==
             ~w(specification calibration harness_validation candidate_result hermeticity repeatability adversarial_challenge mutation_assessment human_observation environment_attestation)

    assert Verification.validity_states() == ~w(valid suspect invalid expired)
    assert evidence["schema_version"] == "conveyor.verification_evidence@1"
    assert evidence["evidence_kind"] == "candidate_result"
    assert evidence["validity"] == "valid"
    assert evidence["environment_fingerprint_digest"] == "sha256:env"

    human_observation =
      Verification.new_evidence!(%{
        evidence
        | "producer_kind" => "human_observer",
          "producer_ref" => "human-decision:review-1",
          "evidence_kind" => "human_observation",
          "evidence_digest" => "sha256:human"
      })

    assert human_observation["producer_kind"] == "human_observer"
    assert human_observation["evidence_kind"] == "human_observation"

    assert_raise ArgumentError, ~r/validity must be one of/, fn ->
      Verification.new_evidence!(%{evidence | "validity" => "quarantined"})
    end
  end

  test "active VerificationWaiver requires human ownership, expiry, controls, and autonomy cap" do
    waiver =
      Verification.new_waiver!(%{
        verification_obligation_id: "verification_obligation:sha256:abc",
        human_decision_id: "human-decision:waive-1",
        reason: "Provider outage blocks repeatability sample.",
        compensating_control_refs: ["control:manual-review", "control:observe-only"],
        max_autonomy: "observe_only",
        owner: "principal-engineer",
        expires_at: "2026-06-26T00:00:00Z",
        status: :active
      })

    assert Verification.waiver_statuses() == ~w(active expired revoked superseded)
    assert waiver["schema_version"] == "conveyor.verification_waiver@1"
    assert waiver["human_decision_id"] == "human-decision:waive-1"

    assert waiver["compensating_control_refs"] == [
             "control:manual-review",
             "control:observe-only"
           ]

    assert waiver["max_autonomy"] == "observe_only"
    assert waiver["status"] == "active"

    assert_raise ArgumentError, ~r/active waiver requires compensating_control_refs/, fn ->
      Verification.new_waiver!(%{waiver | "compensating_control_refs" => []})
    end

    assert_raise ArgumentError, ~r/active waiver requires human_decision_id/, fn ->
      Verification.new_waiver!(%{waiver | "human_decision_id" => nil})
    end
  end
end
