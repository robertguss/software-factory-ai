defmodule Conveyor.ContractCriticLensesTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractCritic.Lenses

  test "multi-lens critic runs every required lens without approval authority" do
    result =
      Lenses.review(%{
        contract_id: "agent-brief-contract:SLC-001",
        evidence_refs: ["test-pack:SLC-001"],
        lens_inputs: %{
          "scope_delta" => %{status: "pass"},
          "test_loopholes" => %{
            status: "fail",
            findings: ["AC-001 can pass without checking deleted rows"]
          },
          "security" => %{
            status: "fail",
            findings: ["secret path is not excluded"]
          }
        }
      })

    assert result.authority_effect == :none
    assert result.can_approve? == false
    assert result.can_lock? == false

    assert Lenses.required_lenses() == [
             "intent_fidelity",
             "scope_delta",
             "principal_engineering",
             "interface_compatibility",
             "test_loopholes",
             "reliability_observability",
             "security",
             "cost_simplification",
             "hidden_decision",
             "approval_cognitive_load"
           ]

    assert Enum.count(result.lens_results) == 10
    assert result.overall_status == :challenged

    assert Enum.any?(
             result.lens_results,
             &(&1["lens"] == "test_loopholes" and &1["status"] == "fail")
           )

    assert Enum.any?(
             result.lens_results,
             &(&1["lens"] == "security" and &1["status"] == "fail")
           )

    assert result.disagreements == [
             %{
               "status_set" => ["fail", "pass"],
               "lenses" => ["scope_delta", "security", "test_loopholes"]
             }
           ]
  end
end
