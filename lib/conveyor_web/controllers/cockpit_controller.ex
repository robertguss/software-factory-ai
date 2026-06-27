defmodule ConveyorWeb.CockpitController do
  use ConveyorWeb, :controller

  import Inertia.Controller

  alias ConveyorWeb.Live.Cockpit.GraphProjection

  # The Inertia page is its own mount node; no inner app layout.
  plug :put_layout, false

  @doc """
  Seed the cockpit shell props — the plan/run identity the React page opens the
  Channel with. The graph itself does NOT come through here; it streams over the
  cockpit Channel (`graph:init` / `node:patch`). The default plan id is resolved
  server-side when none is given.
  """
  def index(conn, params) do
    plan_id = params["plan_id"] || GraphProjection.default_plan_id()
    run_id = params["run_id"] || "default"

    conn
    |> assign_prop(:plan_id, plan_id)
    |> assign_prop(:run_id, run_id)
    |> render_inertia("Cockpit")
  end
end
