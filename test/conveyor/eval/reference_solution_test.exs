defmodule Conveyor.Eval.ReferenceSolutionTest do
  use Conveyor.DataCase, async: false

  import Conveyor.AgentRunnerConformance

  alias Conveyor.AgentRunner.ReferenceSolution
  alias Conveyor.Eval.BridgeFixtures

  @moduletag :eval
  @known_good "samples/tasks_service/.conveyor/canary/known_good.patch"

  test "ReferenceSolution satisfies the adapter conformance suite applying known_good" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "ref-conformance",
        adapter_name: "reference_solution",
        patch_ref: @known_good
      )

    result =
      assert_adapter_conforms!(ReferenceSolution, fixture, reference_patch: fixture.patch_ref)

    assert result.metadata["adapter"] == "reference_solution"
    assert result.metadata["reference_patch"] =~ "known_good.patch"
  end
end
