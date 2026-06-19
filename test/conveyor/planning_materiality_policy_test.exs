defmodule Conveyor.PlanningMaterialityPolicyTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.MaterialityPolicy

  test "human gated mode ignores implementer self-declared nonmaterial weakening" do
    decision =
      MaterialityPolicy.adjudicate(%{
        mode: "human_gated",
        originating_role: "implementer",
        requested_materiality: "nonmaterial",
        materiality_labels: ["acceptance_weakened"],
        touched_areas: ["acceptance_criteria"]
      })

    assert decision["mode"] == "human_gated"
    assert decision["materiality"] == "material"
    assert decision["authority_decision"] == "require_human"
    assert decision["auto_accept"] == false
    assert "implementer_self_declaration_ignored" in decision["reason_codes"]
    assert "authority_meaning_changed" in decision["reason_codes"]
  end

  test "shadow adjudication records narrow would-accept but still requires human authority" do
    decision =
      MaterialityPolicy.adjudicate(%{
        mode: "shadow_adjudication",
        originating_role: "contract_author",
        materiality_labels: ["compatibility_superset"],
        touched_areas: ["compatibility"],
        preserves_existing_consumers: true,
        contract_author_verdict: "accepted",
        before_attempt_started: true,
        active_qualification_grant: true,
        negotiation_round: 1,
        negotiation_round_limit: 3
      })

    assert decision["materiality"] == "nonmaterial"
    assert decision["authority_decision"] == "require_human"
    assert decision["shadow_decision"] == "would_auto_accept"
    assert decision["auto_accept"] == false
  end

  test "pre-attempt auto accept is limited to narrow safe deltas" do
    accepted =
      MaterialityPolicy.adjudicate(%{
        mode: "pre_attempt_auto_accept",
        originating_role: "contract_author",
        materiality_labels: ["type_clarification"],
        touched_areas: ["type"],
        preserves_existing_consumers: true,
        contract_author_verdict: "accepted",
        before_attempt_started: true,
        active_qualification_grant: true,
        negotiation_round: 2,
        negotiation_round_limit: 3
      })

    rejected =
      MaterialityPolicy.adjudicate(%{
        mode: "pre_attempt_auto_accept",
        originating_role: "contract_author",
        materiality_labels: ["compatibility_weakened"],
        touched_areas: ["public_compatibility"],
        preserves_existing_consumers: true,
        contract_author_verdict: "accepted",
        before_attempt_started: true,
        active_qualification_grant: true,
        negotiation_round: 1,
        negotiation_round_limit: 3
      })

    assert accepted["materiality"] == "nonmaterial"
    assert accepted["authority_decision"] == "auto_accept"
    assert accepted["auto_accept"] == true
    assert accepted["creates_new_authority_chain"] == true

    assert rejected["materiality"] == "material"
    assert rejected["authority_decision"] == "require_human"
    assert rejected["auto_accept"] == false
    assert "public_compatibility_touched" in rejected["reason_codes"]
  end
end
