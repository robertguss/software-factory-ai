defmodule Conveyor.Conductor.Child do
  @moduledoc """
  Minimal GenServer implementation for named Phase 0 supervisor children.

  The concrete behavior for these services lands in later beads; this skeleton
  gives the OTP topology stable child names from day one.
  """

  defmacro __using__(_opts) do
    quote do
      use GenServer

      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(opts), do: {:ok, Map.new(opts)}
    end
  end
end
