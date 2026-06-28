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

  test "plan@1 work_dependency kind enum stays a subset of the work_dependency_kind vocabulary" do
    plan_schema = read_json!("docs/schemas/conveyor.plan@1.json")

    plan_kind_enum =
      plan_schema["$defs"]["work_dependency"]["properties"]["kind"]["enum"]

    registry = read_json!("docs/schemas/registry.json")

    vocab_values =
      Enum.find_value(registry["vocabularies"], fn vocabulary ->
        vocabulary["key"] == "work_dependency_kind" && vocabulary["values"]
      end)

    assert is_list(plan_kind_enum) and plan_kind_enum != []
    assert is_list(vocab_values) and vocab_values != []

    # The vocabulary may be a strict superset (e.g. `advisory` is in the vocab but
    # deliberately excluded from plan@1). The dangerous drift is a schema enum value
    # that escaped the vocabulary, which this subset check catches.
    assert MapSet.subset?(MapSet.new(plan_kind_enum), MapSet.new(vocab_values)),
           "plan@1 work_dependency.kind enum #{inspect(plan_kind_enum)} must be a subset of " <>
             "registry work_dependency_kind vocabulary #{inspect(vocab_values)}; " <>
             "extra values escaped the registry vocabulary: " <>
             "#{inspect(MapSet.difference(MapSet.new(plan_kind_enum), MapSet.new(vocab_values)) |> MapSet.to_list())}"
  end

  defp schema_path(schema_name), do: "docs/schemas/#{schema_name}.json"

  defp valid_example_path(schema_name), do: "docs/schemas/examples/#{schema_name}.valid.json"

  defp invalid_example_path(schema_name),
    do: "docs/schemas/examples/#{schema_name}.invalid.missing-schema-version.json"

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
