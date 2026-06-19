defmodule Conveyor.ContractCriticRepairDiffTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractCritic.RepairDiff

  test "emits typed comparison and reuses unaffected pass outputs" do
    result =
      RepairDiff.compare!(%{
        rejected_artifact_refs: ["agent-brief-contract:SLC-001"],
        before: %{
          digest: "sha256:before",
          changed_artifact_refs: ["agent-brief-contract:SLC-001"],
          pass_outputs: %{
            "interface_graph" => %{
              input_refs: ["interface:tasks"],
              output_ref: "pass:interface-old"
            },
            "test_pack" => %{input_refs: ["test-pack:SLC-001"], output_ref: "pass:test-old"}
          }
        },
        after: %{
          digest: "sha256:after",
          changed_artifact_refs: ["agent-brief-contract:SLC-001"],
          pass_inputs: %{
            "interface_graph" => ["interface:tasks"],
            "test_pack" => ["test-pack:SLC-001-v2"]
          }
        },
        materiality: "material",
        authority_effect: "none"
      })

    assert result["schema_version"] == "conveyor.repair_diff@1"
    assert result["before_digest"] == "sha256:before"
    assert result["after_digest"] == "sha256:after"
    assert result["comparison_type"] == "material"
    assert result["authority_effect"] == "none"
    assert result["reused_pass_outputs"] == ["pass:interface-old"]
    assert result["invalidated_passes"] == ["test_pack"]
    assert result["repair_diff_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  test "blocks repairs that change artifacts outside the rejected scope" do
    assert {:error, findings} =
             RepairDiff.compare(%{
               rejected_artifact_refs: ["agent-brief-contract:SLC-001"],
               before: %{digest: "sha256:before", changed_artifact_refs: []},
               after: %{
                 digest: "sha256:after",
                 changed_artifact_refs: ["policy-bundle:global"]
               },
               materiality: "breaking",
               authority_effect: "policy_changed"
             })

    assert [%{rule_key: "repair.scope_expanded", severity: :blocking}] = findings
  end
end
