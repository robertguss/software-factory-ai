defmodule Conveyor.RunSpecForgeTest do
  @moduledoc """
  Characterization tests for `Conveyor.RunSpecForge` — forges the next attempt's
  immutable RunSpec from the prior attempt's frozen spec (the M2 rework retry path).
  """
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec
  alias Conveyor.RunSpecForge

  defp prior(label) do
    fixture = create_artifact_run!(blob_root: temp_dir!(label))

    spec =
      RunSpec
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.id == fixture.run_attempt.run_spec_id))

    {fixture.run_attempt, spec}
  end

  test "forges the next attempt's spec, preserving slice/base and bumping attempt_no" do
    {attempt, spec} = prior("forge-bump")

    forged = RunSpecForge.forge_retry!(attempt, spec)

    assert forged.attempt_no == spec.attempt_no + 1
    assert forged.slice_id == spec.slice_id
    assert forged.base_commit == spec.base_commit
    assert forged.contract_lock_sha256 == spec.contract_lock_sha256
    # The retry spec is content-addressed over the new attempt -> a fresh digest.
    refute forged.run_spec_sha256 == spec.run_spec_sha256
  end

  test "merges the rung's agent_profile_patch over the prior snapshot" do
    {attempt, spec} = prior("forge-rung")

    rung = %{
      "rung" => "codex_reasoning_effort:high",
      "agent_profile_patch" => %{"codex_reasoning_effort" => "high"}
    }

    forged = RunSpecForge.forge_retry!(attempt, spec, rung: rung)

    assert forged.agent_profile_snapshot == %{
             "adapter" => "pi",
             "codex_reasoning_effort" => "high"
           }
  end

  test "threads the new run_spec_sha256 into every station's input and output" do
    {attempt, spec} = prior("forge-stations")

    forged = RunSpecForge.forge_retry!(attempt, spec)

    for station <- forged.station_plan["stations"] do
      assert station["input"]["run_spec_sha256"] == forged.run_spec_sha256
      assert station["output"]["run_spec_sha256"] == forged.run_spec_sha256
    end
  end

  test "raises when the prior spec does not belong to the prior attempt" do
    {attempt, spec} = prior("forge-mismatch")

    # The forged spec belongs to no attempt yet, so it cannot be `attempt`'s prior spec.
    forged = RunSpecForge.forge_retry!(attempt, spec)

    assert_raise ArgumentError, fn -> RunSpecForge.forge_retry!(attempt, forged) end
  end
end
