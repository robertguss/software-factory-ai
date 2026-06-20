defmodule Conveyor.QualificationGateSchemaTest do
  use ExUnit.Case, async: true

  @schema_names ~w(
    conveyor.qualification_grant@1
    conveyor.qualification_scope_lattice@1
    conveyor.admission_permit@1
    conveyor.permit_checkpoint@1
    conveyor.qualification_impact@1
  )

  test "P15-B8 qualification gate schemas validate examples and are registered" do
    registry = read_json!("docs/schemas/registry.json")
    registered_versions = Enum.map(registry["schemas"], & &1["schema_version"])

    for schema_name <- @schema_names do
      schema = schema_name |> schema_path() |> read_json!() |> JSV.build!()

      assert {:ok, valid} =
               schema_name
               |> valid_example_path()
               |> read_json!()
               |> JSV.validate(schema)

      assert valid["schema_version"] == schema_name
      assert_contract(schema_name, valid)

      assert {:error, _error} =
               schema_name
               |> invalid_example_path()
               |> read_json!()
               |> JSV.validate(schema)

      assert schema_name in registered_versions
    end
  end

  defp schema_path(schema_name), do: "docs/schemas/#{schema_name}.json"

  defp valid_example_path(schema_name), do: "docs/schemas/examples/#{schema_name}.valid.json"

  defp invalid_example_path(schema_name),
    do: "docs/schemas/examples/#{schema_name}.invalid.missing-schema-version.json"

  defp assert_contract("conveyor.qualification_grant@1", valid) do
    assert valid["status"] in ["active", "expired", "revoked", "superseded"]
    assert valid["max_autonomy"] == "local_dev"
    assert valid["success_rate_bands"] != []
    assert valid["invalidation_triggers"] != []
  end

  defp assert_contract("conveyor.qualification_scope_lattice@1", valid) do
    assert valid["worst_required_stratum_result"] in ["pass", "fail", "unassessed"]
    assert valid["inheritance_default"] == "none"
  end

  defp assert_contract("conveyor.admission_permit@1", valid) do
    assert valid["qualification_grant_id"] != nil
    assert valid["permit_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    assert valid["expires_at"] > valid["issued_at"]
  end

  defp assert_contract("conveyor.permit_checkpoint@1", valid) do
    assert valid["result"] in ["valid", "invalid", "suspended"]
    assert is_list(valid["reason_codes"])
    assert valid["trace_id"] != nil
  end

  defp assert_contract("conveyor.qualification_impact@1", valid) do
    assert valid["changed_subject_refs"] != []
    assert valid["required_requalification_case_ids"] != []
    assert valid["report_ref"] != nil
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
