defmodule Conveyor.ContractCriticCheapestWrongTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractCritic.CheapestWrong

  test "emits stable ContractChallengeCases for cheapest wrong implementations" do
    result =
      CheapestWrong.challenge!(%{
        contract_id: "agent-brief-contract:SLC-001",
        approved_intent_refs: ["CLAIM-001"],
        evidence_refs: ["test-pack:SLC-001"],
        attacks: [
          %{
            attack_key: "ignore_deleted_rows",
            written_contract_satisfied_by: "Return completed=true rows but ignore deleted_at.",
            approved_intent_violated: "Deleted rows must never be visible.",
            evidence_gap_refs: ["AC-001", "FAL-001"],
            materiality: "material",
            repair_proposal: "Add acceptance criterion and falsifier for deleted rows."
          }
        ]
      })

    assert result.authority_effect == :none

    assert [%{"schema_version" => "conveyor.contract_challenge_case@1"} = challenge] =
             result.challenge_cases

    assert challenge["rule_key"] == "contract_critic.cheapest_wrong.ignore_deleted_rows"
    assert challenge["contract_id"] == "agent-brief-contract:SLC-001"
    assert challenge["evidence_refs"] == ["test-pack:SLC-001", "AC-001", "FAL-001"]
    assert challenge["materiality"] == "material"

    assert challenge["repair_proposal"] ==
             "Add acceptance criterion and falsifier for deleted rows."

    assert challenge["challenge_case_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end
end
