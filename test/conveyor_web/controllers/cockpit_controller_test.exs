defmodule ConveyorWeb.CockpitControllerTest do
  use ConveyorWeb.ConnCase, async: true

  # The cockpit shell renders as an Inertia page; the graph itself arrives over
  # the Channel, so the dead render only needs the mount node + the shell props
  # (plan/run identity) the React page opens the socket with.
  test "GET /cockpit returns the Cockpit Inertia dead render with run_id", %{conn: conn} do
    html = conn |> get(~p"/cockpit") |> html_response(200)

    assert html =~ ~s(id="app")
    assert html =~ "data-page"
    assert html =~ "Cockpit"
    # run_id defaults to the live frontier and is carried as a prop.
    assert html =~ "default"
    assert html =~ "/assets/app.js"
  end

  test "GET /cockpit?run_id=run-7 carries the requested run into the props", %{conn: conn} do
    html = conn |> get(~p"/cockpit?run_id=run-7") |> html_response(200)
    assert html =~ "run-7"
  end
end
