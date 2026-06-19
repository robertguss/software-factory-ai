defmodule Conveyor.BehaviorLockRunSchemaTest do
  use ExUnit.Case, async: true

  @schema_name "conveyor.behavior_lock_run@1"
  @schema_path "docs/schemas/#{@schema_name}.json"
  @valid_example_path "docs/schemas/examples/#{@schema_name}.valid.json"
  @invalid_example_path "docs/schemas/examples/#{@schema_name}.invalid.missing-schema-version.json"

  test "BehaviorLockRun schema validates examples and is registered" do
    schema = @schema_path |> read_json!() |> JSV.build!()

    assert {:ok, valid} =
             @valid_example_path
             |> read_json!()
             |> JSV.validate(schema)

    assert valid["schema_version"] == @schema_name
    assert valid["status"] in ["no_divergence_observed", "diverged", "inconclusive"]
    assert valid["equivalence_claim"] == "bounded_observation_only"

    assert {:error, _error} =
             @invalid_example_path
             |> read_json!()
             |> JSV.validate(schema)

    registry = read_json!("docs/schemas/registry.json")
    registered_versions = Enum.map(registry["schemas"], & &1["schema_version"])
    assert @schema_name in registered_versions
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
