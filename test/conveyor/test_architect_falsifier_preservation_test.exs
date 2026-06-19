defmodule Conveyor.TestArchitectFalsifierPreservationTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestArchitect.Artifacts
  alias Conveyor.TestArchitect.FalsifierPreservation
  alias Conveyor.Verification

  @seed_attrs %{
    verification_obligation_id: "verification_obligation:sha256:abc",
    acceptance_ref: "AC-001",
    source_kind: :property,
    falsifying_condition_ref: "compiler-falsifier:condition/property-1",
    compiler_pass_ref: "compiler-pass:falsifier-seed@1",
    created_at: "2026-06-19T00:00:00Z"
  }

  test "translated TestSpecifications satisfy compiler-derived falsifier seeds" do
    seed = Verification.new_falsifier_seed!(@seed_attrs)
    spec = test_specification!(seed)

    result =
      FalsifierPreservation.evaluate!(
        [seed],
        [spec],
        [],
        created_at: "2026-06-19T00:01:00Z"
      )

    assert result.report["result"] == "satisfied"
    assert result.report["translated_seed_ids"] == [seed["id"]]
    assert [%{"action" => "translated", "preserved_ref" => preserved_ref}] = result.preservations
    assert preserved_ref == spec["id"]
  end

  test "explicit stronger approved evidence may supersede a seed" do
    seed = Verification.new_falsifier_seed!(@seed_attrs)

    result =
      FalsifierPreservation.evaluate!(
        [seed],
        [],
        [
          %{
            falsifier_seed_id: seed["id"],
            verification_obligation_id: seed["verification_obligation_id"],
            stronger_evidence_ref: "verification_evidence:sha256:stronger",
            human_decision_id: "human-decision:supersede-falsifier"
          }
        ],
        created_at: "2026-06-19T00:02:00Z"
      )

    assert result.report["result"] == "satisfied"
    assert result.report["superseded_seed_ids"] == [seed["id"]]
    assert [%{"action" => "superseded"}] = result.preservations
  end

  test "dropped compiler-derived seeds block the report" do
    seed = Verification.new_falsifier_seed!(@seed_attrs)

    result =
      FalsifierPreservation.evaluate!(
        [seed],
        [],
        [],
        created_at: "2026-06-19T00:03:00Z"
      )

    assert result.report["result"] == "blocked"
    assert result.report["blocked_seed_ids"] == [seed["id"]]
    assert [%{"rule_key" => "falsifier_seed.dropped"}] = result.report["findings"]
  end

  defp test_specification!(seed) do
    Artifacts.new_test_specification!(%{
      slice_id: "SLC-001",
      test_id: "tests/test_property.py::test_property_seed",
      role: "property",
      verification_obligation_refs: [seed["verification_obligation_id"]],
      acceptance_refs: [seed["acceptance_ref"]],
      interface_refs: [],
      expected_on_base: "fail",
      base_calibration_expectation: "fail_expected_reason",
      expected_base_reason: "compiler falsifier fails on base",
      expected_on_candidate: "pass",
      failure_signature_policy: "stable_reason",
      compiler_falsifier_seed_refs: [seed["id"]],
      hermeticity_requirements: ["no_network"],
      environment_requirements: [],
      hidden_from_implementer: false,
      result_adapter: "Conveyor.TestResultAdapter.JUnit",
      claim_refs: []
    })
  end
end
