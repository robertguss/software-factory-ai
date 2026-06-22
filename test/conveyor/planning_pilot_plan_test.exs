defmodule Conveyor.PlanningPilotPlanTest do
  use ExUnit.Case, async: true

  @plan_path "test/fixtures/phase-2/p2-b7/pilot-plan.json"

  @required_coverage ~w(
    fork_join
    public_interface
    migration_compatibility
    ambiguity
    alternative_candidate
    amendment_path
    parked_path
    human_verification
  )

  test "P2-B7 pilot plan covers the required graph interface risk and human classes" do
    plan = @plan_path |> File.read!() |> Jason.decode!()
    slices = plan["slices"]
    slice_ids = MapSet.new(slices, & &1["slice_id"])
    epic_ids = MapSet.new(plan["epics"], & &1["epic_id"])

    assert length(slices) in 8..12
    assert MapSet.size(epic_ids) >= 2
    assert slices |> Enum.map(& &1["epic_id"]) |> MapSet.new() |> MapSet.size() >= 2

    for slice <- slices do
      assert slice["epic_id"] in epic_ids

      for dependency <- slice["depends_on"] do
        assert dependency in slice_ids
      end
    end

    coverage =
      slices
      |> Enum.flat_map(& &1["coverage_classes"])
      |> MapSet.new()

    for required <- @required_coverage do
      assert MapSet.member?(coverage, required)
    end

    assert Enum.any?(slices, &(&1["human_verification_only"] == true))

    assert Enum.any?(
             slices,
             &Enum.any?(&1["obligations"], fn obligation ->
               obligation["verification_mode"] == "human_only"
             end)
           )

    assert Enum.any?(slices, &(&1["parked_path"] == true))
    assert Enum.any?(slices, &(&1["amendment"] == true))
  end
end
