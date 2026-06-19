defmodule Conveyor.ContractAuthorTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractForge.ContractAuthor

  test "materializes a normalized AgentBrief contract from the contract-author RoleView" do
    result =
      ContractAuthor.materialize(%{
        "slice_id" => "SLC-001",
        "role_view" => %{
          "claims" => ["CLAIM-001"],
          "interfaces" => ["public.tasks.v1"],
          "constraints" => ["CON-001"],
          "bounded_context" => ["REQ-001", "DEC-001"]
        },
        "behavior" => %{
          "current" => "Tasks list omits completion state.",
          "desired" => "Tasks list includes completion state."
        },
        "archetype" => "crud_endpoint",
        "change_class" => "public_interface_change",
        "acceptance_criteria" => [
          %{
            "id" => "AC-001",
            "text" => "List tasks returns completion state.",
            "machine_checkable" => true,
            "verification_stage" => "unit",
            "positive_examples" => ["completed task includes completed=true"],
            "negative_examples" => ["missing completed field"],
            "boundary_examples" => ["empty list"],
            "abuse_examples" => ["unknown fields ignored"],
            "non_goal_examples" => ["authentication"],
            "falsifying_conditions" => ["completed task listed without completed=true"],
            "required_test_refs" => ["test/tasks_test.exs::completion"]
          }
        ],
        "authorized_scope" => %{
          "description" => "Task list serialization only.",
          "protected_paths" => ["lib/tasks/**", "test/tasks/**"]
        },
        "rollout" => %{"environment" => "ci-linux", "intent" => "normal release"},
        "recovery" => %{"intent" => "revert serializer change"},
        "out_of_scope" => ["authentication"]
      })

    assert result.status == :passed
    assert result.authority_effect == :none
    assert result.role_view["claims"] == ["CLAIM-001"]
    assert result.contract["schema_version"] == "conveyor.agent_brief_contract@1"
    assert result.contract["source_refs"]["claims"] == ["CLAIM-001"]
    # bounded_context is partitioned by ref class, not duplicated into both arrays.
    assert result.contract["source_refs"]["requirements"] == ["REQ-001"]
    assert result.contract["source_refs"]["decisions"] == ["DEC-001"]

    assert [%{"schema_version" => "conveyor.verification_obligation@1"}] =
             result.verification_obligations

    assert [%{"family" => "table_negative_row"} | _] = result.falsifier_seeds
    assert result.findings == []

    assert_schema_valid!(result.contract)
  end

  defp assert_schema_valid!(contract) do
    schema =
      "docs/schemas/conveyor.agent_brief_contract@1.json"
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(contract, schema)
  end
end
