defmodule Conveyor.PlanningPilotSelectionTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PilotSelection

  @plan_path "docs/phase-2/p2-b7/pilot-plan.json"
  @schema_path "docs/schemas/conveyor.pilot_selection@1.json"

  test "freezes every machine-executable slice before the first selected attempt" do
    plan = read_plan!()

    selection =
      PilotSelection.freeze(%{
        planning_bundle_id: "planning-bundle:contract-foundry-pilot:r1",
        frozen_at: "2026-06-19T11:42:00Z",
        implementation_started?: false,
        plan: plan
      })

    executable_slice_ids =
      plan["slices"]
      |> Enum.filter(& &1["machine_executable"])
      |> Enum.map(& &1["slice_id"])
      |> Enum.sort()

    assert selection["schema_version"] == "conveyor.pilot_selection@1"
    assert selection["selected_slice_ids"] == executable_slice_ids
    assert selection["excluded_slice_ids_with_reasons"] == []
    assert selection["selection_digest"]["value"] =~ ~r/^[0-9a-f]{64}$/
    assert selection["required_coverage_classes"] == PilotSelection.required_coverage_classes()
    assert_schema_valid!(selection)
  end

  test "blocks selection after implementation has started" do
    result =
      PilotSelection.freeze(%{
        planning_bundle_id: "planning-bundle:contract-foundry-pilot:r1",
        frozen_at: "2026-06-19T11:42:00Z",
        implementation_started?: true,
        plan: read_plan!()
      })

    assert result["status"] == "blocked"
    assert "implementation_already_started" in result["blocking_reasons"]
    assert result["pilot_selection"] == nil
  end

  defp assert_schema_valid!(resource) do
    schema =
      @schema_path
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(resource, schema)
  end

  defp read_plan!, do: @plan_path |> File.read!() |> Jason.decode!()
end
