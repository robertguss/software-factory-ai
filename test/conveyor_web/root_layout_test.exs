defmodule ConveyorWeb.RootLayoutTest do
  @moduledoc """
  Smoke test for the browser runtime (U1). The root layout is the only HTML
  document wrapper; it must emit the esbuild bundle so LiveView's JS client loads
  and `connected?/1` can become true in a real browser. We assert against the
  dead (HTTP GET) render of `/parked` because that is where the root layout is
  present — the connected LiveView diff does not carry the static layout.
  """
  use ConveyorWeb.ConnCase, async: true

  test "the root layout emits the app.js bundle, csrf token, and phx-track-static",
       %{conn: conn} do
    html = conn |> get(~p"/parked") |> html_response(200)

    assert html =~ ~s(src="/assets/app.js")
    assert html =~ ~s(href="/assets/app.css")
    assert html =~ "phx-track-static"
    assert html =~ ~s(name="csrf-token")
    assert html =~ "<!DOCTYPE html>"
  end
end
