defmodule Conveyor.Jobs.ReconcileStaleEffects do
  @moduledoc "Periodic stale side-effect reconciliation worker skeleton."
  use Conveyor.Jobs.WorkerStub, queue: :maintenance
end
