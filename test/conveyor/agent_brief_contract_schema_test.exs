defmodule Conveyor.AgentBriefContractSchemaTest do
  use ExUnit.Case, async: true

  @schema_name "conveyor.agent_brief_contract@1"

  test "upgraded AgentBrief contract schema validates its golden example and registry entry" do
    schema = "docs/schemas/#{@schema_name}.json" |> read_json!() |> JSV.build!()

    assert {:ok, valid} =
             "docs/schemas/examples/#{@schema_name}.valid.json"
             |> read_json!()
             |> JSV.validate(schema)

    assert valid["schema_version"] == @schema_name
    assert valid["behavior"]["current"] != ""
    assert valid["behavior"]["desired"] != ""

    assert [%{"positive_examples" => [_], "falsifying_conditions" => [_]}] =
             valid["acceptance_criteria"]

    assert [%{"evidence_requirements" => [_]}] = valid["verification_obligations"]
    assert valid["authorized_scope"]["protected_paths"] != []
    assert valid["risk"]["required_review_lenses"] != []
    assert valid["rollout"]["environment"] != nil
    assert valid["recovery"]["intent"] != nil
    assert valid["claim_coverage"] != []

    assert {:error, _error} =
             "docs/schemas/examples/#{@schema_name}.invalid.missing-schema-version.json"
             |> read_json!()
             |> JSV.validate(schema)

    registry = read_json!("docs/schemas/registry.json")
    registered_versions = Enum.map(registry["schemas"], & &1["schema_version"])
    assert @schema_name in registered_versions
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
