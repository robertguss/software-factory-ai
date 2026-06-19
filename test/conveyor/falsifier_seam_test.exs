defmodule Conveyor.FalsifierSeamTest do
  use ExUnit.Case, async: true

  alias Conveyor.Verification

  @seed_attrs %{
    verification_obligation_id: "verification_obligation:sha256:abc",
    acceptance_ref: "AC-001",
    source_kind: :property,
    falsifying_condition_ref: "compiler-falsifier:condition/property-1",
    compiler_pass_ref: "compiler-pass:falsifier-seed@1",
    created_at: "2026-06-19T00:00:00Z"
  }

  test "compiler falsifier seeds are content addressed and tied to an obligation" do
    seed = Verification.new_falsifier_seed!(@seed_attrs)
    same_seed = Verification.new_falsifier_seed!(@seed_attrs)

    other_source =
      Verification.new_falsifier_seed!(%{@seed_attrs | source_kind: :interface_schema})

    assert Verification.falsifier_source_kinds() ==
             ~w(example forbidden_behavior property metamorphic_relation interface_schema)

    assert seed["schema_version"] == "conveyor.compiler_falsifier_seed@1"
    assert seed["id"] == same_seed["id"]
    assert seed["id"] != other_source["id"]
    assert seed["verification_obligation_id"] == "verification_obligation:sha256:abc"
    assert seed["source_kind"] == "property"
  end

  test "preserved and superseded falsifier seeds satisfy the preservation seam" do
    seed = Verification.new_falsifier_seed!(@seed_attrs)

    preserved =
      Verification.new_falsifier_preservation!(%{
        falsifier_seed_id: seed["id"],
        verification_obligation_id: seed["verification_obligation_id"],
        action: :preserved,
        preserved_ref: "test-pack:falsifier/property-1",
        created_at: "2026-06-19T00:01:00Z"
      })

    report = Verification.evaluate_falsifier_preservation([seed], [preserved])

    assert preserved["schema_version"] == "conveyor.falsifier_preservation@1"
    assert report["result"] == "satisfied"
    assert report["preserved_seed_ids"] == [seed["id"]]
    assert report["blocked_seed_ids"] == []

    superseded =
      Verification.new_falsifier_preservation!(%{
        falsifier_seed_id: seed["id"],
        verification_obligation_id: seed["verification_obligation_id"],
        action: :superseded,
        stronger_evidence_ref: "verification_evidence:sha256:stronger",
        human_decision_id: "human-decision:supersede-falsifier",
        created_at: "2026-06-19T00:02:00Z"
      })

    superseded_report = Verification.evaluate_falsifier_preservation([seed], [superseded])

    assert superseded_report["result"] == "satisfied"
    assert superseded_report["superseded_seed_ids"] == [seed["id"]]
  end

  test "dropping a compiler seed is a blocking integrity failure" do
    seed = Verification.new_falsifier_seed!(@seed_attrs)

    report = Verification.evaluate_falsifier_preservation([seed], [])

    assert report["schema_version"] == "conveyor.falsifier_preservation_report@1"
    assert report["result"] == "blocked"
    assert report["blocked_seed_ids"] == [seed["id"]]
    assert [%{"rule_key" => "falsifier_seed.dropped"}] = report["findings"]
  end
end
