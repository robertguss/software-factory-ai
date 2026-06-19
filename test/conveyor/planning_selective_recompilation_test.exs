defmodule Conveyor.PlanningSelectiveRecompilationTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SelectiveRecompilation

  test "reruns only invalidated pure passes and affected stochastic roles" do
    plan =
      SelectiveRecompilation.plan(%{
        impact_confidence: 0.93,
        invalidated_refs: ["interface_contract:payments-api", "contract:checkout"],
        proven_valid_refs: ["requirement:admin", "policy_bundle:main"],
        valid_approval_refs: ["approval:admin"],
        passes: [
          %{
            pass_key: "contract_author:checkout",
            role_kind: "pure",
            input_refs: ["interface_contract:payments-api", "policy_bundle:main"],
            output_ref: "contract:checkout",
            output_digest: "sha256:checkout"
          },
          %{
            pass_key: "critic:checkout",
            role_kind: "stochastic",
            input_refs: ["contract:checkout"],
            output_ref: "critic_dossier:checkout",
            output_digest: "sha256:critic"
          },
          %{
            pass_key: "contract_author:admin",
            role_kind: "pure",
            input_refs: ["requirement:admin", "policy_bundle:main"],
            output_ref: "contract:admin",
            output_digest: "sha256:admin",
            approval_ref: "approval:admin"
          }
        ]
      })

    assert plan["status"] == "selective"
    assert plan["fail_wide"] == false
    assert plan["rerun_passes"] == ["contract_author:checkout", "critic:checkout"]

    assert plan["retained_outputs"] == [
             %{
               "pass_key" => "contract_author:admin",
               "output_ref" => "contract:admin",
               "output_digest" => "sha256:admin",
               "approval_ref" => "approval:admin"
             }
           ]
  end

  test "low confidence fails wide and retains no digests or approvals" do
    plan =
      SelectiveRecompilation.plan(%{
        impact_confidence: 0.41,
        invalidated_refs: ["policy_bundle:main"],
        proven_valid_refs: ["requirement:admin"],
        valid_approval_refs: ["approval:admin"],
        passes: [
          %{
            pass_key: "contract_author:checkout",
            role_kind: "pure",
            input_refs: [],
            output_ref: "contract:checkout"
          },
          %{
            pass_key: "contract_author:admin",
            role_kind: "pure",
            input_refs: ["requirement:admin"],
            output_ref: "contract:admin",
            output_digest: "sha256:admin",
            approval_ref: "approval:admin"
          }
        ]
      })

    assert plan["status"] == "low_confidence_fail_wide"
    assert plan["fail_wide"] == true
    assert plan["rerun_passes"] == ["contract_author:admin", "contract_author:checkout"]
    assert plan["retained_outputs"] == []
    assert "impact_confidence_low" in plan["blocking_reasons"]
  end
end
