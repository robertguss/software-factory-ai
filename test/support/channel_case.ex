defmodule ConveyorWeb.ChannelCase do
  @moduledoc """
  Test case for the cockpit Channel — `Phoenix.ChannelTest` plus the SQL
  sandbox, since the Channel reads the projection from Postgres.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ConveyorWeb.Endpoint

      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import ConveyorWeb.ChannelCase
    end
  end

  setup tags do
    Conveyor.DataCase.setup_sandbox(tags)
    :ok
  end
end
