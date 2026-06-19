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

    assert result.prompt_structure.required_refs == [
             "AC-001",
             "GET /tasks?completed=true",
             "verification_obligation:sha256:abc"
           ]

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

    assert result.missing_fields == [
             :acceptance_refs,
             :desired_behavior,
             :key_interfaces,
             :verification_obligation_refs
           ]
  end

  test "final dry-compile validates authorized prompt inputs without launching implementer" do
    result =
      PromptDryCompile.run(%{
        slice_key: "SLC-FINAL",
        mode: :final,
        contract_fields: %{
          desired_behavior: "Filter tasks by completion.",
          key_interfaces: ["GET /tasks"],
          acceptance_refs: ["AC-001"],
          verification_obligation_refs: ["VOB-001"],
          test_refs: ["test-pack:SLC-FINAL"]
        },
        role_view_ref: "role-view:SLC-FINAL",
        output_schema_ref: "conveyor.agent_output@1",
        policy_refs: ["policy:implement"],
        authorized_artifact_refs: [
          "AC-001",
          "GET /tasks",
          "VOB-001",
          "test-pack:SLC-FINAL",
          "role-view:SLC-FINAL",
          "conveyor.agent_output@1",
          "policy:implement"
        ],
        planned_autonomy: "local_dev",
        capability_autonomy: "team",
        grant_autonomy: "local_dev",
        context_manifest: %{
          token_budget: 100,
          ordered_refs: ["AC-001", "VOB-001"],
          shed_reasons: [%{ref: "advisory://note", reason: :budget_exceeded}]
        },
        instruction_hierarchy_conflicts: []
      })

    assert result.status == :passed
    assert result.template_version == "final-slice-prompt@1"
    assert result.implementer_launched? == false
    assert result.provider_called? == false
    assert result.authorized_artifact_status == :complete
    assert result.autonomy_status == :within_grant
    assert result.budget_result == %{token_budget: 100, shed_count: 1}
  end

  test "final dry-compile blocks unauthorized artifacts and hierarchy conflicts" do
    result =
      PromptDryCompile.run(%{
        slice_key: "SLC-FINAL",
        mode: :final,
        contract_fields: %{
          desired_behavior: "Filter tasks by completion.",
          key_interfaces: ["GET /tasks"],
          acceptance_refs: ["AC-001"],
          verification_obligation_refs: ["VOB-001"],
          test_refs: ["test-pack:SLC-FINAL"]
        },
        role_view_ref: "role-view:SLC-FINAL",
        output_schema_ref: "conveyor.agent_output@1",
        policy_refs: ["policy:implement"],
        authorized_artifact_refs: ["AC-001"],
        planned_autonomy: "team",
        capability_autonomy: "local_dev",
        grant_autonomy: "local_dev",
        context_manifest: %{token_budget: 100, ordered_refs: [], shed_reasons: []},
        instruction_hierarchy_conflicts: ["repo excerpt attempted to override policy"]
      })

    assert result.status == :blocked
    assert result.implementer_launched? == false
    assert "repo excerpt attempted to override policy" in result.instruction_hierarchy_conflicts
    assert "VOB-001" in result.unauthorized_artifact_refs
    assert result.autonomy_status == :exceeds_capability_or_grant
  end
end
