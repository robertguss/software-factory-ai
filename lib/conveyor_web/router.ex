defmodule ConveyorWeb.Router do
  use ConveyorWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ConveyorWeb do
    pipe_through :api
  end
end
