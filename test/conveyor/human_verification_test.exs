defmodule Conveyor.HumanVerificationTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestArchitect.HumanVerification

  test "procedures represent human judgment honestly and cap autonomy" do
    procedure =
      HumanVerification.procedure!(%{
        verification_obligation_id: "verification_obligation:sha256:human",
        acceptance_ref: "AC-HUMAN",
        author_ref: "test-architect:writer-1",
        observer_role: "human_observer",
        procedure: "Compare UX tone against the brand rubric.",
        rubric_ref: "rubric:brand-tone",
        max_autonomy: "observe_only"
      })

    assert procedure["schema_version"] == "conveyor.human_verification_procedure@1"
    assert procedure["required_evidence_kind"] == "human_observation"
    assert procedure["machine_promotable"] == false
    assert procedure["max_autonomy"] == "observe_only"
    assert procedure["weak_evidence_route"]["to"] == "test-architect:writer-1"
    assert procedure["weak_evidence_route"]["not_to"] == "implementer"
  end

  test "accepted observations emit human_observation evidence and cannot be promoted" do
    procedure = procedure!()

    evidence =
      HumanVerification.to_evidence!(
        procedure,
        %{
          observer_ref: "human:reviewer-1",
          observation_ref: "artifact:human-observation-1",
          evidence_digest: "sha256:human-observation",
          validity: "valid",
          observed_at: "2026-06-19T00:00:00Z"
        }
      )

    assert evidence["producer_kind"] == "human_observer"
    assert evidence["evidence_kind"] == "human_observation"
    assert evidence["validity"] == "valid"

    assert_raise ArgumentError,
                 ~r/human verification cannot be promoted to machine evidence/,
                 fn ->
                   HumanVerification.promote_to_machine_evidence!(evidence)
                 end
  end

  test "weak human evidence routes to its author rather than the implementer" do
    result =
      HumanVerification.review_observation(
        procedure!(),
        %{
          observer_ref: "human:reviewer-1",
          observation_ref: "artifact:vague-human-observation",
          validity: "suspect",
          weakness_reason: "rubric criterion not addressed"
        }
      )

    assert result.status == :needs_author_revision
    assert result.route_to == "test-architect:writer-1"
    assert result.not_to == "implementer"
    assert result.finding["rule_key"] == "human_verification.weak_evidence"
  end

  defp procedure! do
    HumanVerification.procedure!(%{
      verification_obligation_id: "verification_obligation:sha256:human",
      acceptance_ref: "AC-HUMAN",
      author_ref: "test-architect:writer-1",
      observer_role: "human_observer",
      procedure: "Compare UX tone against the brand rubric.",
      rubric_ref: "rubric:brand-tone",
      max_autonomy: "observe_only"
    })
  end
end
