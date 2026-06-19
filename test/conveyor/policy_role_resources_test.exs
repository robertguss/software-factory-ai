defmodule Conveyor.PolicyRoleResourcesTest do
  use ExUnit.Case, async: true

  @schema_names ~w(
    conveyor.policy_bundle@1
    conveyor.decision_contract@1
    conveyor.policy_decision@1
    conveyor.tool_contract@1
    conveyor.role_view@1
    conveyor.enforcement_profile@1
  )

  @required_decision_keys ~w(
    run.start
    planning.start
    provider.egress
    qualification.grant_issue
    qualification.grant_admit
    adapter.autonomy_ceiling
    artifact.role_visibility
    tool.invoke
    cassette.accept
    verification_obligation.satisfied
    recovery.auto_apply
    amendment.materiality
    approval.invalidate
    contract.lock
    slice.ready
    budget.reserve
    emergency_stop.resume
  )

  test "P15-A2 resource schemas validate golden examples and reject missing schema_version" do
    for schema_name <- @schema_names do
      schema = schema_name |> schema_path() |> read_json!() |> JSV.build!()

      assert {:ok, _validated} =
               schema_name
               |> valid_example_path()
               |> read_json!()
               |> JSV.validate(schema)

      assert {:error, _error} =
               schema_name
               |> invalid_example_path()
               |> read_json!()
               |> JSV.validate(schema)
    end
  end

  test "DecisionContract registry contains all required policy decision keys" do
    registry = read_json!("docs/policies/decision-contracts.json")
    keys = Enum.map(registry["decision_contracts"], & &1["decision_key"])

    for key <- @required_decision_keys do
      assert key in keys
    end
  end

  defp schema_path(schema_name), do: "docs/schemas/#{schema_name}.json"

  defp valid_example_path(schema_name), do: "docs/schemas/examples/#{schema_name}.valid.json"

  defp invalid_example_path(schema_name),
    do: "docs/schemas/examples/#{schema_name}.invalid.missing-schema-version.json"

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
