defmodule Conveyor.PlanningRunReconstructionTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.RunReconstruction
  alias Conveyor.Planning.RunReconstruction.ResumeState

  defp outcome(slice_id, sequence, status),
    do:
      {slice_id,
       %{"run_id" => "r", "slice_id" => slice_id, "sequence" => sequence, "status" => status}}

  defp reconstruct(order, outcomes),
    do: RunReconstruction.reconstruct("r", order, outcomes: Map.new(outcomes))

  test "folds passed slices and finds the in-flight resume point" do
    state =
      reconstruct(["SLICE-001", "SLICE-002", "SLICE-003"], [
        outcome("SLICE-001", 1, "passed"),
        outcome("SLICE-002", 2, "passed")
      ])

    assert %ResumeState{} = state
    assert state.passed_slice_ids == MapSet.new(["SLICE-001", "SLICE-002"])
    assert state.start_index == 2
    assert state.in_flight_slice == "SLICE-003"
  end

  test "a parked slice is reconstructed as blocked, not passed" do
    state =
      reconstruct(["SLICE-001", "SLICE-002", "SLICE-003"], [
        outcome("SLICE-001", 1, "passed"),
        outcome("SLICE-002", 2, "parked")
      ])

    assert state.passed_slice_ids == MapSet.new(["SLICE-001"])
    assert state.blocked == MapSet.new(["SLICE-002"])
    # SLICE-003 has no committed outcome -> it is the resume point.
    assert state.in_flight_slice == "SLICE-003"
  end

  test "a started-only run (no slice outcomes) resumes at slice 1" do
    state = reconstruct(["SLICE-001", "SLICE-002"], [])

    assert state.start_index == 0
    assert state.in_flight_slice == "SLICE-001"
    assert state.passed_slice_ids == MapSet.new()
  end

  test "a fully-committed run has no in-flight slice" do
    state =
      reconstruct(["SLICE-001", "SLICE-002"], [
        outcome("SLICE-001", 1, "passed"),
        outcome("SLICE-002", 2, "passed")
      ])

    assert state.start_index == 2
    assert state.in_flight_slice == nil
  end
end
