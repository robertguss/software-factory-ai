defmodule ConveyorWeb.Layouts do
  @moduledoc """
  Application layouts.

  Holds the root layout — the only HTML document wrapper in the app. It emits the
  `/assets/app.js` bundle so LiveView's JS client loads and connects in a real
  browser. Before this module existed `ConveyorWeb` referenced it (the controller
  `:layouts` option) but it was never defined, the browser pipeline ran
  `put_root_layout false`, and no page carried a `<script>` — so `connected?/1`
  was always false outside `LiveViewTest`.
  """
  use ConveyorWeb, :html

  @doc """
  The root layout: the outer HTML document shared by every page.

  The browser pipeline installs it via `put_root_layout/2`; LiveViews render into
  `@inner_content`. The `<head>` loads the esbuild bundle, which is what brings
  the realtime loop online in the browser.
  """
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>{assigns[:page_title] || "Conveyor"}</title>
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
