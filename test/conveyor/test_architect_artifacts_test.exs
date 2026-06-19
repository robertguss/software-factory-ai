defmodule Conveyor.TestArchitectArtifactsTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestArchitect.Artifacts

  @schema_names ~w(
    conveyor.test_specification@1
    conveyor.test_pack_patch@1
    conveyor.challenge_case@1
  )

  test "builds schema-valid TestSpecification, TestPack patch, and hidden challenge artifacts" do
    bundle =
      Artifacts.build!(%{
        slice_id: "SLC-021",
        agent_brief_contract_id: "agent-brief-contract:SLC-021",
        test_pack_id: "test-pack:SLC-021",
        workspace_contract_id: "test-architect-workspace:SLC-021",
        environment_policy: %{
          network: "none",
          clock: "fixed",
          rng: "seeded",
          locale: "C.UTF-8"
        },
        nondeterminism_policy: %{
          retries: 3,
          failure_signature_policy: "stable_reason"
        },
        test_specs: [
          %{
            test_id: "tests/test_tasks.py::test_filter_completed_true",
            role: "acceptance_new",
            verification_obligation_refs: ["VOB-AC-021"],
            acceptance_refs: ["AC-021"],
            interface_refs: ["http.get.tasks"],
            expected_on_base: "fail",
            base_calibration_expectation: "fail_expected_reason",
            expected_base_reason: "completed filter not implemented",
            expected_on_candidate: "pass",
            failure_signature_policy: "stable_reason",
            compiler_falsifier_seed_refs: ["FAL-AC-021-1"],
            hermeticity_requirements: ["no_network", "fixed_clock", "seeded_rng"],
            environment_requirements: ["python:3.12"],
            hidden_from_implementer: false,
            result_adapter: "Conveyor.TestResultAdapter.JUnit",
            claim_refs: ["CLAIM-021"]
          }
        ],
        patch_files: [
          %{
            path: "tests/test_tasks.py",
            mode: "create",
            content_digest: "sha256:test-file"
          }
        ],
        challenge_cases: [
          %{
            challenge_id: "challenge:SLC-021:hidden-completed-filter",
            verification_obligation_refs: ["VOB-AC-021"],
            acceptance_refs: ["AC-021"],
            compiler_falsifier_seed_refs: ["FAL-AC-021-1"],
            hidden_from_implementer: true,
            expected_on_candidate: "fail",
            reason: "completed=false must not satisfy completed=true filter"
          }
        ]
      })

    assert [%{"schema_version" => "conveyor.test_specification@1"} = spec] =
             bundle.test_specifications

    assert spec["verification_obligation_refs"] == ["VOB-AC-021"]
    assert spec["acceptance_refs"] == ["AC-021"]
    assert spec["expected_on_base"] == "fail"
    assert spec["expected_base_reason"] == "completed filter not implemented"
    assert spec["result_adapter"] == "Conveyor.TestResultAdapter.JUnit"
    assert spec["test_specification_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/

    assert %{"schema_version" => "conveyor.test_pack_patch@1"} = patch = bundle.test_pack_patch
    assert patch["test_pack_id"] == "test-pack:SLC-021"
    assert patch["test_specification_ids"] == [spec["id"]]
    assert patch["environment_policy"]["network"] == "none"
    assert patch["nondeterminism_policy"]["failure_signature_policy"] == "stable_reason"
    assert [%{"mode" => "create", "path" => "tests/test_tasks.py"}] = patch["patch_files"]

    assert [%{"schema_version" => "conveyor.challenge_case@1"} = challenge] =
             bundle.challenge_cases

    assert challenge["hidden_from_implementer"] == true
    assert challenge["verification_obligation_refs"] == ["VOB-AC-021"]
    assert challenge["compiler_falsifier_seed_refs"] == ["FAL-AC-021-1"]

    assert_schema_valid!(spec)
    assert_schema_valid!(patch)
    assert_schema_valid!(challenge)
  end

  test "rejects tests that do not map to obligations and acceptance criteria" do
    assert_raise ArgumentError, ~r/verification_obligation_refs must not be empty/, fn ->
      Artifacts.new_test_specification!(%{
        slice_id: "SLC-022",
        test_id: "tests/test_tasks.py::test_missing_mapping",
        role: "acceptance_new",
        verification_obligation_refs: [],
        acceptance_refs: ["AC-022"],
        expected_on_base: "fail",
        base_calibration_expectation: "fail_expected_reason",
        expected_base_reason: "missing mapping",
        expected_on_candidate: "pass",
        failure_signature_policy: "stable_reason",
        result_adapter: "Conveyor.TestResultAdapter.JUnit"
      })
    end
  end

  test "P2-B2 artifact schemas are registered" do
    registry = read_json!("docs/schemas/registry.json")
    registered_versions = Enum.map(registry["schemas"], & &1["schema_version"])

    for schema_name <- @schema_names do
      assert schema_name in registered_versions
    end
  end

  defp assert_schema_valid!(artifact) do
    schema_name = artifact["schema_version"]
    schema = schema_name |> schema_path() |> read_json!() |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(artifact, schema)
  end

  defp schema_path(schema_name), do: "docs/schemas/#{schema_name}.json"
  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
