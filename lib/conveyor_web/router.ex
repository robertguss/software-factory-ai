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
  end

  scope "/", ConveyorWeb do
    pipe_through :browser

    live "/runs", RunViewerLive, :index
    live "/parked", ParkedQueueLive, :index
  end

  scope "/api", ConveyorWeb do
    pipe_through :api
  end
end
