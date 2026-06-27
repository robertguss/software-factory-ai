defmodule ConveyorWeb.Router do
  use ConveyorWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ConveyorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Inertia.Plug
  end

  scope "/", ConveyorWeb do
    pipe_through :browser

    # /runs is the React/Inertia cockpit (U10 cutover); the graph streams over the
    # cockpit Channel. /parked stays a LiveView.
    get "/runs", CockpitController, :index
    live "/parked", ParkedQueueLive, :index
  end

  scope "/api", ConveyorWeb do
    pipe_through :api
  end
end
