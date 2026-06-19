defmodule Conveyor.SchemaRegistryResourcesTest do
  use ExUnit.Case, async: true

  @schema_names ~w(
    conveyor.digest_ref@1
    conveyor.resource_ref@1
    conveyor.subject_ref@1
    conveyor.schema_registry_entry@1
    conveyor.attestation_statement@1
    conveyor.lifecycle_contract@1
    conveyor.root_manifest@1
  )

  @required_vocabularies ~w(
    materiality_class
    failure_class
    verification_stage
    evidence_validity
    artifact_sensitivity
    work_dependency_kind
    interface_lock_level
    policy_decision_result
    run_mode
    authority_level
    retention_class
  )

  test "P15-A1 resource schemas validate golden examples and reject missing schema_version" do
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

  test "machine-readable schema registry declares entries and shared vocabularies" do
    registry = read_json!("docs/schemas/registry.json")

    assert registry["schema_version"] == "conveyor.schema_registry@1"

    registered_versions = Enum.map(registry["schemas"], & &1["schema_version"])

    for schema_name <- @schema_names do
      assert schema_name in registered_versions
    end

    vocabulary_keys = Enum.map(registry["vocabularies"], & &1["key"])

    for vocabulary <- @required_vocabularies do
      assert vocabulary in vocabulary_keys
    end
  end

  defp schema_path(schema_name), do: "docs/schemas/#{schema_name}.json"

  defp valid_example_path(schema_name), do: "docs/schemas/examples/#{schema_name}.valid.json"

  defp invalid_example_path(schema_name),
    do: "docs/schemas/examples/#{schema_name}.invalid.missing-schema-version.json"

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
