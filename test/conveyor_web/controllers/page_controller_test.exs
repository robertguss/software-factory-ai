defmodule ConveyorWeb.PageControllerTest do
  use ConveyorWeb.ConnCase, async: true

  # U2 baseline: the Inertia dead render must emit the React mount node
  # (`<div id="app" data-page=...>`) with the controller's props serialized in,
  # while the shared root layout still ships the esbuild bundle. Retired with the
  # /hello route at the /runs cutover (U10).
  test "GET /hello returns the Inertia dead render carrying props", %{conn: conn} do
    html = conn |> get(~p"/hello") |> html_response(200)

    assert html =~ ~s(id="app")
    assert html =~ "data-page"
    assert html =~ "Hello"
    assert html =~ "Cockpit foundation"
    assert html =~ "/assets/app.js"
  end
end
