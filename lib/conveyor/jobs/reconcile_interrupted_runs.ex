defmodule Conveyor.Jobs.ReconcileInterruptedRuns do
  @moduledoc """
  Maintenance worker that resumes or parks runs interrupted by a crash (M6 ledger U6).

  Enqueued at application start so an unattended run that died (deploy, OOM, host reboot)
  is picked back up. Mirrors `Conveyor.Jobs.ReconcileStaleEffects`.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Conveyor.Planning.RunReconciler

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> opts_from_args()
    |> RunReconciler.reconcile!()

    :ok
  end

  defp opts_from_args(args) do
    case Map.get(args, "resume_attempt_cap") || Map.get(args, :resume_attempt_cap) do
      cap when is_integer(cap) -> [resume_attempt_cap: cap]
      _ -> []
    end
  end
end
