defmodule Conveyor.ContractCriticRepairLoopTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractCritic.RepairLoop

  test "allows at most two automatic repair rounds by default" do
    assert RepairLoop.next_action(%{station: "contract_author", completed_rounds: 0}) == :repair
    assert RepairLoop.next_action(%{station: "contract_author", completed_rounds: 1}) == :repair
    assert RepairLoop.next_action(%{station: "contract_author", completed_rounds: 2}) == :park
  end

  test "parks oscillating or non-progressing repairs with evidence" do
    result =
      RepairLoop.evaluate(%{
        artifact_digests: ["sha256:a", "sha256:b", "sha256:a"],
        finding_counts: [3, 3, 3],
        evidence_refs: ["contract_challenge_case:sha256:abc"]
      })

    assert result.status == :parked
    assert result.reason in [:oscillation, :non_progress]
    assert result.evidence_refs == ["contract_challenge_case:sha256:abc"]
  end

  test "routes material plan constraint interface or acceptance changes to amendment" do
    result =
      RepairLoop.route_change(%{
        change_class: "acceptance",
        materiality: "material",
        weakens_policy_or_acceptance: false
      })

    assert result == {:amendment_required, %{change_class: "acceptance", materiality: "material"}}
  end

  test "rejects repairs that weaken policy or acceptance without normal authority" do
    assert {:error, finding} =
             RepairLoop.route_change(%{
               change_class: "policy",
               materiality: "material",
               weakens_policy_or_acceptance: true,
               authority_ref: nil
             })

    assert finding.rule_key == "repair.policy_or_acceptance_weakening"
    assert finding.severity == :blocking
  end
end
