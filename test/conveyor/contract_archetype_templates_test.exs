defmodule Conveyor.ContractArchetypeTemplatesTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractForge.ArchetypeTemplates

  @required_archetypes ~w(
    bugfix_regression
    crud_endpoint
    pure_refactor
    schema_migration
    dependency_update
    public_interface_change
    security_hardening
    performance
    configuration
    custom
  )

  test "declares deterministic minimum obligations for every supported archetype" do
    templates = ArchetypeTemplates.all()

    assert Enum.sort(Map.keys(templates)) == Enum.sort(@required_archetypes)

    for {key, template} <- templates do
      assert template["archetype"] == key
      assert template["minimum_obligations"] != []
      assert template["required_review_lenses"] != []
      assert template["falsifier_seed_families"] != []
    end
  end

  test "custom increases critic and approval scrutiny" do
    custom = ArchetypeTemplates.fetch!("custom")

    assert "critic:extra_lens" in custom["required_review_lenses"]
    assert custom["approval_scrutiny"] == "heightened"
    assert custom["minimum_obligations"] |> Enum.any?(&(&1["id"] == "custom_scope_justification"))
  end
end
