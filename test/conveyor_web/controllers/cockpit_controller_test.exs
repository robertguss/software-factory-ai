defmodule ConveyorWeb.CockpitControllerTest do
  use ConveyorWeb.ConnCase, async: true

  # /runs is now the React cockpit (U10 cutover): a plain Inertia dead render, not
  # a LiveView mount. The graph itself arrives over the Channel, so the dead
  # render only needs the mount node + the shell props (plan/run identity) the
  # React page opens the socket with.
  test "GET /runs returns the Cockpit Inertia dead render with run_id", %{conn: conn} do
    html = conn |> get(~p"/runs") |> html_response(200)

    assert html =~ ~s(id="app")
    assert html =~ "data-page"
    assert html =~ "Cockpit"
    # run_id defaults to the live frontier and is carried as a prop.
    assert html =~ "default"
    assert html =~ "/assets/app.js"

    # It is a controller dead render, not a LiveView mount — no LiveView markers.
    refute html =~ "phx-hook"
    refute html =~ ~s(data-phx-main)
  end

  test "GET /runs?run_id=run-7 carries the requested run into the props", %{conn: conn} do
    html = conn |> get(~p"/runs?run_id=run-7") |> html_response(200)
    assert html =~ "run-7"
  end
end
