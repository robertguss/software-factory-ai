defmodule Conveyor.ContractAuditTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestArchitect.ContractAudit

  @schema_name "conveyor.contract_audit@1"

  test "builds a dimensional ContractAudit report without an opaque score" do
    audit =
      ContractAudit.report!(%{
        slice_id: "SLC-021",
        agent_brief_id: "agent-brief-contract:SLC-021",
        test_pack_id: "test-pack:SLC-021",
        planning_run_id: "planning-run:sha256:abc",
        compiler_version: "compiler:2026-06-19",
        decision: "needs_revision",
        stages: [
          %{
            key: "oracle_feasibility",
            status: "blocked",
            finding_refs: ["oracle_feasibility.boundary_unclear"]
          },
          %{
            key: "integrity_gate",
            status: "passed",
            finding_refs: []
          }
        ],
        quality_dimensions: %{
          "traceability" => "passed",
          "claim_and_source_anchor_coverage" => "passed",
          "scope_boundedness" => "passed",
          "interface_clarity" => "passed",
          "interface_compatibility" => "passed",
          "dependency_clarity" => "passed",
          "atomicity_safety" => "passed",
          "acceptance_falsifiability" => "needs_revision"
        },
        report_ref: "artifact:contract-audit/SLC-021"
      })

    assert audit["schema_version"] == @schema_name
    assert audit["decision"] == "needs_revision"
    assert audit["quality_dimensions"]["acceptance_falsifiability"] == "needs_revision"
    refute Map.has_key?(audit, "score")
    assert audit["contract_audit_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/

    assert_schema_valid!(audit)
  end

  test "ContractAudit schema is registered" do
    registry = read_json!("docs/schemas/registry.json")
    registered_versions = Enum.map(registry["schemas"], & &1["schema_version"])

    assert @schema_name in registered_versions
  end

  defp assert_schema_valid!(artifact) do
    schema = @schema_name |> schema_path() |> read_json!() |> JSV.build!()
    assert {:ok, _validated} = JSV.validate(artifact, schema)
  end

  defp schema_path(schema_name), do: "docs/schemas/#{schema_name}.json"
  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
