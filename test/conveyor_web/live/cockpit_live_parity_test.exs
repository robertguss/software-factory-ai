defmodule ConveyorWeb.CockpitLiveParityTest do
  @moduledoc """
  U6 — the /runs cutover. Proves the cockpit is a faithful projection (R17,
  ADR-21), observe-only (R18), and honest about liveness (KTD8): the Stalled
  signal is driven by a real stored `StationRun.started_at` against the cap, not
  a hand-set state column. Runs `async: false` because it pins the per-slice cap
  (disabled in test config) via `put_env`.
  """
  use ConveyorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Conveyor.CockpitFixtures
  alias Conveyor.Planning.RunReconstruction
  alias ConveyorWeb.Live.Cockpit.GraphProjection

  setup do
    previous = Application.get_env(:conveyor, :serial_driver_slice_wall_clock_ms)
    Application.put_env(:conveyor, :serial_driver_slice_wall_clock_ms, 3_600_000)

    on_exit(fn ->
      Application.put_env(:conveyor, :serial_driver_slice_wall_clock_ms, previous)
    end)

    :ok
  end

  test "the cockpit projection's outcome states match the reconstruction authority (R17, ADR-21)" do
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

    # The reconstruction authority: the committed run.slice_outcome fold both the
    # CLI/static report and the cockpit read from.
    authority = RunReconstruction.load_outcomes(run_id)
    model = GraphProjection.build(plan.id, run_id: run_id, now: now)

    assert map_size(authority) == 3

    for {stable_key, payload} <- authority do
      node = Enum.find(model.nodes, &(&1.id == s[stable_key].id))

      assert node.state == parity_state(payload["status"]),
             "#{stable_key}: cockpit #{node.state} != authority #{payload["status"]}"
    end
  end

  test "CockpitLive at /runs exposes no domain-write affordance (R18)", %{conn: conn} do
    %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

    {:ok, view, html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
    panel_html = render_hook(view, "node:select", %{"id" => s["SLICE-001"].id})

    for content <- [html, panel_html] do
      refute content =~ "phx-submit"
      refute content =~ "mark_external"
    end
  end

  test "no faked liveness: an over-cap running slice is Stalled, a within-cap one is not (KTD8)",
       %{conn: conn} do
    %{plan: plan, slices: s} =
      CockpitFixtures.seed_plan([{"SLICE-001", :in_progress}, {"SLICE-002", :in_progress}], [])

    # Real stored started_at — a production-representative over-cap station, not a
    # hand-set column.
    CockpitFixtures.seed_running_station(
      s["SLICE-001"],
      DateTime.add(DateTime.utc_now(), -2, :hour)
    )

    CockpitFixtures.seed_running_station(
      s["SLICE-002"],
      DateTime.add(DateTime.utc_now(), -5, :minute)
    )

    {:ok, view, _html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
    render_hook(view, "dag:mounted", %{})
    assert_push_event(view, "graph:init", %{nodes: nodes})

    assert Enum.find(nodes, &(&1.id == s["SLICE-001"].id)).state == :stalled
    assert Enum.find(nodes, &(&1.id == s["SLICE-002"].id)).state == :running
  end

  test "/runs now serves the cockpit (the old run viewer is gone)", %{conn: conn} do
    %{plan: plan} = CockpitFixtures.seed_plan([{"SLICE-001", :ready}], [])

    {:ok, _view, html} = live(conn, ~p"/runs?plan_id=#{plan.id}")
    assert html =~ ~s(phx-hook="Dag")
  end

  test "/parked is unaffected by the /runs swap", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/parked")
    assert html =~ "Needs a human"
  end

  defp parity_state("passed"), do: :done
  defp parity_state("parked"), do: :parked
  defp parity_state("skipped"), do: :skipped
end
