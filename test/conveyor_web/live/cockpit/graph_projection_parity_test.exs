defmodule ConveyorWeb.Live.Cockpit.GraphProjectionParityTest do
  @moduledoc """
  The cockpit projection is a faithful read of the reconstruction authority (R17,
  ADR-21): a run's committed `run.slice_outcome` fold — the same source the
  CLI/static report reads — must yield the same per-slice states the cockpit
  shows. Transport-independent (relocated from the retired CockpitLive parity
  test at the /runs cutover): it compares `GraphProjection.build/2` to
  `RunReconstruction` directly, below any LiveView or Channel.
  """
  use ConveyorWeb.ConnCase, async: true

  alias Conveyor.CockpitFixtures
  alias Conveyor.Planning.RunReconstruction
  alias ConveyorWeb.Live.Cockpit.GraphProjection

  test "the projection's outcome states match the reconstruction authority (R17, ADR-21)" do
    now = DateTime.utc_now()

    %{plan: plan, slices: s} =
      CockpitFixtures.seed_plan(
        [{"SLICE-001", :ready}, {"SLICE-002", :ready}, {"SLICE-003", :ready}],
        [{"SLICE-001", "SLICE-002"}, {"SLICE-002", "SLICE-003"}]
      )

    run_id = "run-parity"
    CockpitFixtures.seed_run_started(run_id, ["SLICE-001", "SLICE-002", "SLICE-003"], now)
    CockpitFixtures.seed_outcome(run_id, "SLICE-001", "passed", 1, now)
    CockpitFixtures.seed_outcome(run_id, "SLICE-002", "parked", 2, now)
    CockpitFixtures.seed_outcome(run_id, "SLICE-003", "skipped", 3, now)

    authority = RunReconstruction.load_outcomes(run_id)
    model = GraphProjection.build(plan.id, run_id: run_id, now: now)

    assert map_size(authority) == 3

    for {stable_key, payload} <- authority do
      node = Enum.find(model.nodes, &(&1.id == s[stable_key].id))

      assert node.state == parity_state(payload["status"]),
             "#{stable_key}: cockpit #{node.state} != authority #{payload["status"]}"
    end
  end

  defp parity_state("passed"), do: :done
  defp parity_state("parked"), do: :parked
  defp parity_state("skipped"), do: :skipped
end
