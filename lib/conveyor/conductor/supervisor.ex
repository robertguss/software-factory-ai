defmodule Conveyor.Conductor.Supervisor do
  @moduledoc """
  Supervisor for the deterministic conductor services described in the Phase 1
  topology.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Conveyor.Ledger,
      Conveyor.Telemetry,
      Conveyor.Config,
      Conveyor.Policy.Engine,
      Conveyor.Security.Redactor,
      Conveyor.Artifacts.Projector,
      Conveyor.EventOutbox,
      Conveyor.Effects.Reconciler,
      Conveyor.Sandbox.Reaper
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
