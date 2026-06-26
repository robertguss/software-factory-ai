defmodule ConveyorWeb.CockpitLiveEmptyTest do
  @moduledoc """
  Empty-instance resilience (review fix #1): `/runs` on a fresh instance — before
  any plan is imported — has a `nil` model, yet still subscribes and schedules the
  periodic Stalled tick. The tick must be a no-op, not a crash loop.
  """
  use ConveyorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the Stalled tick does not crash an empty (no-plan) cockpit (#1)", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/runs")
    assert html =~ "No plan to display yet"

    # Fire the periodic tick directly: with no model it must short-circuit, not
    # dereference `nil.nodes`.
    send(view.pid, :stalled_tick)

    # The view is still alive and rendering after the tick.
    assert render(view) =~ "No plan to display yet"
  end
end
