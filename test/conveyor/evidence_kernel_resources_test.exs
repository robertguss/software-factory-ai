defmodule Conveyor.EvidenceKernelResourcesTest do
  use ExUnit.Case, async: true

  @schema_names ~w(
    conveyor.observed_effect_summary@1
    conveyor.actor_identity@1
    conveyor.actor_action@1
    conveyor.provider_contract@1
    conveyor.provider_egress_record@1
    conveyor.effect_attempt@1
    conveyor.effect_receipt@1
    conveyor.authority_event@1
    conveyor.observation_segment@1
    conveyor.artifact_input@1
    conveyor.artifact_address@1
    conveyor.station_run_lease_ext@1
    conveyor.dependency_resolution_manifest@1
    conveyor.emergency_stop_state@1
    conveyor.budget_envelope@1
    conveyor.budget_reservation@1
    conveyor.adapter_health_state@1
    conveyor.battery_case@1
    conveyor.sampling_policy@1
    conveyor.battery_run@1
    conveyor.battery_sample_result@1
    conveyor.battery_case_result@1
    conveyor.human_review_rubric@1
    conveyor.capability_claim@1
    conveyor.effective_capability_set@1
    conveyor.incident_record@1
    conveyor.evidence_comparison@1
    conveyor.failure_diagnosis@1
    conveyor.recovery_proposal@1
    conveyor.plan_source_snapshot@1
    conveyor.plan_revision@1
    conveyor.constraint_set@1
    conveyor.source_anchor@1
    conveyor.claim_set@1
    conveyor.planning_spec@1
  )

  test "P15-A2/A3 seam resource schemas validate golden examples and reject missing schema_version" do
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

  test "schema registry declares the P15-A2/A3 seam resources" do
    registry = read_json!("docs/schemas/registry.json")
    registered_versions = Enum.map(registry["schemas"], & &1["schema_version"])

    for schema_name <- @schema_names do
      assert schema_name in registered_versions
    end
  end

  defp schema_path(schema_name), do: "docs/schemas/#{schema_name}.json"

  defp valid_example_path(schema_name), do: "docs/schemas/examples/#{schema_name}.valid.json"

  defp invalid_example_path(schema_name),
    do: "docs/schemas/examples/#{schema_name}.invalid.missing-schema-version.json"

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
