defmodule Conveyor.PlanningCompatibilityFixturesTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanningSpec

  @fixture_path "test/fixtures/phase-2/p2-a0/schema-pass-compatibility.json"

  test "schema/pass compatibility fixture has stable digests and explicit unknown-schema failure" do
    fixture = @fixture_path |> File.read!() |> Jason.decode!()

    assert fixture["schema_version"] == "conveyor.schema_pass_compatibility@1"
    assert fixture["unknown_schema_failure"] == "unsupported_schema_version"

    first = PlanningSpec.build!(fixture["canonical_semantic_input"])
    second = PlanningSpec.build!(fixture["canonical_semantic_input_reordered"])

    assert first.spec_digest == second.spec_digest
    assert first.pass_graph_digest == fixture["expected_pass_graph_digest"]
  end
end
