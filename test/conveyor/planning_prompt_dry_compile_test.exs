defmodule Conveyor.PlanningPromptDryCompileTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PromptDryCompile

  test "dry-compiles prompt structure from placeholder contract fields only" do
    result =
      PromptDryCompile.run(%{
        slice_key: "SLC-FILTER",
        contract_fields: %{
          current_behavior: "Tasks are listed without completed filtering.",
          desired_behavior: "Tasks can be filtered by completed state.",
          key_interfaces: ["GET /tasks?completed=true"],
          acceptance_refs: ["AC-001"],
          verification_obligation_refs: ["verification_obligation:sha256:abc"]
        },
        critical_context_refs: ["plan_revision:1", "interface_contract:db.tasks.completed"]
      })

    assert result.status == :passed
    assert result.implementer_launched? == false
    assert result.provider_called? == false
    assert result.prompt_structure.template_version == "placeholder-contract-prompt@1"
    assert result.prompt_structure.slice_key == "SLC-FILTER"
    assert result.prompt_structure.required_refs == ["AC-001", "GET /tasks?completed=true", "verification_obligation:sha256:abc"]
    assert result.critical_context_status == :complete
  end

  test "fails before provider when critical prompt references are missing" do
    result =
      PromptDryCompile.run(%{
        slice_key: "SLC-FILTER",
        contract_fields: %{current_behavior: "Current only"},
        critical_context_refs: []
      })

    assert result.status == :blocked
    assert result.implementer_launched? == false
    assert result.provider_called? == false
    assert result.missing_fields == [:acceptance_refs, :desired_behavior, :key_interfaces, :verification_obligation_refs]
  end
end
