defmodule Conveyor.FalsifierSeedDeriverTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractForge.FalsifierSeedDeriver

  test "derives deterministic falsifier seeds from contract examples and interface cases" do
    seeds =
      FalsifierSeedDeriver.derive!(%{
        "acceptance_criteria" => [
          %{
            "id" => "AC-001",
            "falsifying_conditions" => ["missing completed field"],
            "boundary_examples" => ["empty list"],
            "forbidden_predicates" => ["response leaks secret"],
            "property_counterexamples" => ["duplicate id"],
            "metamorphic_relations" => ["sort order does not change membership"],
            "interface_incompatibility_cases" => ["old client cannot parse response"]
          }
        ]
      })

    assert Enum.map(seeds, & &1["family"]) == [
             "table_negative_row",
             "boundary_transform",
             "forbidden_predicate",
             "property_counterexample",
             "metamorphic_relation",
             "interface_incompatibility"
           ]

    assert Enum.all?(seeds, &(&1["source_acceptance_criterion_id"] == "AC-001"))
  end

  test "detects dropped falsifiers as integrity failures" do
    original = [
      %{"seed_id" => "falsifier:AC-001:table_negative_row:0"},
      %{"seed_id" => "falsifier:AC-001:boundary_transform:0"}
    ]

    translated = [%{"seed_id" => "falsifier:AC-001:table_negative_row:0"}]

    assert {:error, findings} = FalsifierSeedDeriver.verify_preserved(original, translated)
    assert Enum.map(findings, & &1.rule_key) == ["falsifier_seed_dropped"]
  end
end
