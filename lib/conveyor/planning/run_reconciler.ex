defmodule Conveyor.Planning.RunReconciler do
  @moduledoc """
  U6: detect interrupted runs from the ledger and route each to resume or park.

  The run ledger (U1/U2) is the run registry: a run is **complete** if its stream has a
  `run.finished` terminal, **reaped** if it has a `run.reaped` terminal (the run-budget
  deadline deliberately halted it), or **interrupted** if it has `run.started` with no
  terminal (a crash). A per-slice `reaped_wall_clock` outcome is a normal parked slice the
  run continued past — it never makes the *run* reaped, so it does not suppress resume.

  Interrupted runs auto-resume, bounded by a resume-attempt cap: after K `run.resumed`
  events for the same run, the run parks for human judgment (a `run.parked` event the
  parked queue surfaces) instead of resuming into the same crash forever.

  Reaped runs already terminated, so they are excluded by their recorded terminal — never a
  special case. Orphaned `RunAttempt` rows left in `:running` by the crash are marked stale.

  Designed to run as a maintenance job at application start (mirroring
  `Conveyor.Effects.Reconciler` / `Conveyor.Jobs.ReconcileStaleEffects`). The actual resume
  invocation is injected (`opts[:resume]`) because rebuilding a run's execution environment
  (agent adapter, workspace, blob root) is `PlanRunner`-coupled; the default rebuilds the
  work-graph input from the `run.started` event and calls `SerialDriver.resume!/3`.
  """

  use Conveyor.Conductor.Child

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Ledger
  alias Conveyor.Planning.SerialDriver
  alias Conveyor.RunAttemptLifecycle

  @default_cap 2
  @lifecycle_types ~w(run.started run.finished run.reaped run.resumed run.parked)

  defmodule Result do
    @moduledoc false
    @type t :: %__MODULE__{
            resumed: [String.t()],
            parked: [String.t()],
            complete: non_neg_integer(),
            failed: [String.t()]
          }
    @enforce_keys [:resumed, :parked, :complete, :failed]
    defstruct [:resumed, :parked, :complete, :failed]
  end

  @spec reconcile!(keyword()) :: Result.t()
  def reconcile!(opts \\ []) do
    cap =
      Keyword.get(
        opts,
        :resume_attempt_cap,
        Application.get_env(:conveyor, :resume_attempt_cap, @default_cap)
      )

    resume = Keyword.get(opts, :resume, &default_resume/2)

    acc =
      lifecycle_events_by_run()
      |> Enum.reduce(%{resumed: [], parked: [], complete: 0, failed: []}, fn {run_id, events},
                                                                             acc ->
        route(run_id, events, cap, resume, acc)
      end)

    if Keyword.get(opts, :mark_orphaned_running, true), do: mark_orphaned_running_stale!()

    %Result{
      resumed: Enum.reverse(acc.resumed),
      parked: Enum.reverse(acc.parked),
      complete: acc.complete,
      failed: Enum.reverse(acc.failed)
    }
  end

  defp route(_run_id, events, cap, resume, acc) do
    started = Enum.find(events, &(&1.type == "run.started"))
    types = MapSet.new(events, & &1.type)
    run_id = started && started.payload["run_id"]

    cond do
      is_nil(started) -> acc
      MapSet.member?(types, "run.finished") -> Map.update!(acc, :complete, &(&1 + 1))
      MapSet.member?(types, "run.reaped") -> park(run_id, started, "reaped", acc)
      MapSet.member?(types, "run.parked") -> push(acc, :parked, run_id)
      resume_count(events) >= cap -> park(run_id, started, "resume_cap_exceeded", acc)
      true -> attempt_resume(run_id, started, events, resume, acc)
    end
  end

  defp attempt_resume(run_id, started, events, resume, acc) do
    # Per-attempt key so each resume increments the cap counter (a single fixed key would
    # dedup and the cap would never advance past one).
    emit!(started, run_id, "run.resumed", "resumed:#{resume_count(events)}", %{})

    try do
      resume.(run_id, input_from(started))
      push(acc, :resumed, run_id)
    rescue
      _error -> push(acc, :failed, run_id)
    end
  end

  defp park(run_id, started, reason, acc) do
    emit!(started, run_id, "run.parked", "parked", %{"reason" => reason})
    push(acc, :parked, run_id)
  end

  defp default_resume(run_id, input), do: SerialDriver.resume!(run_id, input, [])

  defp input_from(started) do
    %{
      "work_graph" => started.payload["work_graph"],
      "selected_slice_ids" => started.payload["slice_ids"]
    }
  end

  defp resume_count(events), do: Enum.count(events, &(&1.type == "run.resumed"))

  defp emit!(started, run_id, type, suffix, extra) do
    Ledger.write!(%{
      project_id: started.project_id,
      idempotency_key: "run:#{run_id}:#{suffix}",
      type: type,
      payload: Map.merge(%{"run_id" => run_id}, extra)
    })
  end

  # Bounded read (KTD4): only the run-lifecycle event types, not the full audit log.
  defp lifecycle_events_by_run do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.type in @lifecycle_types))
    |> Enum.group_by(& &1.payload["run_id"])
  end

  # A crash leaves agent RunAttempts frozen in :running; at boot nothing is live, so they
  # are orphaned. Marking them stale keeps the per-slice state machine clean for the resume's
  # fresh attempts.
  defp mark_orphaned_running_stale! do
    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.status == :running))
    |> Enum.each(
      &RunAttemptLifecycle.transition!(&1, :mark_stale, reason: "orphaned by interrupted run")
    )
  end

  defp push(acc, key, value), do: Map.update!(acc, key, &[value | &1])
end
