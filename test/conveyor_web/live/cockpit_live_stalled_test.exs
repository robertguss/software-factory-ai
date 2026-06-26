defmodule ConveyorWeb.CockpitLiveStalledTest do
  @moduledoc """
  U4 — the Stalled tick (R14). The per-slice wall-clock cap is disabled in test
  config (so the reaper never fires mid-test), so this runs `async: false` and
  pins production's one-hour cap via `put_env` to exercise a real over-cap
  station — honoring KTD8 (no faked liveness): the signal is a real stored
  `StationRun.started_at`, evaluated against the cap, not a hand-set state column.
  """
  use ConveyorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Conveyor.CockpitFixtures

  setup do
    previous = Application.get_env(:conveyor, :serial_driver_slice_wall_clock_ms)
    Application.put_env(:conveyor, :serial_driver_slice_wall_clock_ms, 3_600_000)

    on_exit(fn ->
      Application.put_env(:conveyor, :serial_driver_slice_wall_clock_ms, previous)
    end)

    :ok
  end

  test "the Stalled tick flips a running node once it crosses its cap (AE4, R14)", %{conn: conn} do
    %{plan: plan, slices: s} = CockpitFixtures.seed_plan([{"SLICE-001", :in_progress}], [])

    started = DateTime.utc_now()
    CockpitFixtures.seed_running_station(s["SLICE-001"], started)

    {:ok, view, _html} = live(conn, ~p"/cockpit?plan_id=#{plan.id}")
    render_hook(view, "dag:mounted", %{})

    assert_push_event(view, "graph:init", %{nodes: nodes})
    assert Enum.find(nodes, &(&1.id == s["SLICE-001"].id)).state == :running

    # Tick two hours after the station started: now past the one-hour cap.
    send(view.pid, {:stalled_tick, DateTime.add(started, 2, :hour)})

    assert_push_event(view, "node:patch", %{nodes: patched})
    assert Enum.find(patched, &(&1.id == s["SLICE-001"].id)).state == :stalled
  end
end
