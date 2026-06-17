defmodule Conveyor.ConductorSupervisorTest do
  use ExUnit.Case, async: false

  @conductor_children [
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

  @worker_modules [
    Conveyor.Jobs.RunSlice,
    Conveyor.Jobs.BaselineHealth,
    Conveyor.Jobs.AcceptanceCalibration,
    Conveyor.Jobs.ContextScout,
    Conveyor.Jobs.RunImplementer,
    Conveyor.Jobs.RecordEvidence,
    Conveyor.Jobs.RunReviewer,
    Conveyor.Jobs.RunGate,
    Conveyor.Jobs.RunGateCanary,
    Conveyor.Jobs.ReconcileStaleEffects,
    Conveyor.Jobs.ReapSandboxes,
    Conveyor.Jobs.ProjectArtifacts
  ]

  test "conductor supervisor starts the named phase 1 skeleton services" do
    for child <- @conductor_children do
      assert pid = Process.whereis(child), "#{inspect(child)} is not running"
      assert Process.alive?(pid), "#{inspect(child)} is not alive"
    end
  end

  test "station worker stubs expose Oban worker APIs" do
    for worker <- @worker_modules do
      assert Code.ensure_loaded?(worker), "#{inspect(worker)} is not loaded"
      assert function_exported?(worker, :new, 1), "#{inspect(worker)} is not an Oban worker"
      assert function_exported?(worker, :perform, 1), "#{inspect(worker)} cannot perform jobs"
    end
  end
end
