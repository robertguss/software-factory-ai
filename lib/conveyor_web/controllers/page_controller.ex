defmodule ConveyorWeb.PageController do
  use ConveyorWeb, :controller

  import Inertia.Controller

  # The Inertia page is its own mount node (`<div id="app">`); it goes straight
  # into the root layout's inner_content with no inner app layout in between.
  plug :put_layout, false

  # Temporary Inertia baseline page (U2): proves the server→React render path
  # before the cockpit page lands. Retired with the /hello route at U10.
  def index(conn, _params) do
    conn
    |> assign_prop(:greeting, "Cockpit foundation")
    |> render_inertia("Hello")
  end
end
