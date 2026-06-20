defmodule Conveyor.Eval.ReferenceSolutionTest do
  use Conveyor.DataCase, async: false

  import Conveyor.AgentRunnerConformance

  alias Conveyor.AgentRunner.ReferenceSolution
  alias Conveyor.Eval.BridgeFixtures

  @moduletag :eval
  @known_good "samples/tasks_service/.conveyor/canary/known_good.patch"
  @beads_sample Path.expand("../../../samples/beads_insight", __DIR__)
  @beads_plan Path.join(@beads_sample, "conveyor.plan.yml")
  @beads_slice_007 "samples/beads_insight/.conveyor/canary/reference_slice_007_envelope_assertion.patch"

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

  test "ReferenceSolution does not leave patch backup artifacts in the workspace" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "ref-no-patch-backups",
        adapter_name: "reference_solution",
        sample_path: @beads_sample,
        plan_path: @beads_plan,
        patch_ref: @beads_slice_007
      )

    result =
      assert_adapter_conforms!(ReferenceSolution, fixture, reference_patch: fixture.patch_ref)

    assert result.metadata["reference_patch"] == @beads_slice_007
    assert Path.wildcard(Path.join(fixture.workspace.path, "**/*.orig")) == []
  end
end
