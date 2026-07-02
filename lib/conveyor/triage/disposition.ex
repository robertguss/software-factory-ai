defmodule Conveyor.Triage.Disposition do
  @moduledoc """
  The operator triage disposition engine (uevc.2): the human's verdict on a parked slice, applied as
  an event-sourced, exactly-once closer. The cockpit later calls these same functions.

    * `approve/2` — human-override of the gate abstain: apply the slice's CAPTURED PatchSet to the
      integration target (never re-run the agent), record a human-override approval, transition the
      slice to `:integrated`. A patch conflict fails honestly (suggest rework) and changes nothing.
    * `rework/2` — route the slice back to `:needs_rework` with the operator note; the serial driver
      re-runs it (the note surfaces in the trusted section per the rework-intel epic).
    * `reject/2` — terminal park with a reason; the slice stays `:parked`, recorded as rejected.

  Every disposition is one ledger event (`triage.disposition`) plus a `HumanApproval` evidence row,
  written in a single transaction so effect and event commit together. Exactly-once: a second call
  with the same disposition is a no-op reconcile (the ledger event is the completion marker), so a
  crash between disposition and effect replays cleanly.
  """

  alias Conveyor.Evidence.PatchSetApplicator
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Ledger
  alias Conveyor.Repo
  alias Conveyor.SliceLifecycle

  @type result :: {:ok, map()} | {:error, term()}

  @spec approve(String.t(), keyword()) :: result()
  def approve(slice_id, opts \\ []), do: dispose(slice_id, :approve, opts)

  @spec rework(String.t(), keyword()) :: result()
  def rework(slice_id, opts \\ []), do: dispose(slice_id, :rework, opts)

  @spec reject(String.t(), keyword()) :: result()
  def reject(slice_id, opts \\ []), do: dispose(slice_id, :reject, opts)

  defp dispose(slice_id, type, opts) do
    slice = slice!(slice_id)
    key = idempotency_key(slice_id, type)

    cond do
      not is_nil(existing_event(key)) -> {:ok, %{status: :already_disposed, disposition: type}}
      slice.state != :parked -> {:error, {:not_parked, slice.state}}
      true -> commit(slice, type, key, opts)
    end
  end

  defp commit(slice, type, key, opts) do
    Repo.transaction(fn ->
      case apply_effect(slice, type, opts) do
        {:ok, effect} ->
          approval = record_approval!(slice, type, opts)
          event = write_event!(slice, type, key, approval, opts)
          Map.merge(effect, %{disposition: type, human_approval: approval, ledger_event: event})

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # --- per-disposition effects -----------------------------------------------

  # reject: the slice stays parked (terminal). Nothing to transition — the rejection is the record.
  defp apply_effect(slice, :reject, _opts), do: {:ok, %{slice: slice, terminal_state: :parked}}

  # rework: route back to :needs_rework so the serial driver re-runs it with the operator note.
  defp apply_effect(slice, :rework, opts) do
    updated = transition!(slice, :disposition_rework, opts)
    {:ok, %{slice: updated, terminal_state: :needs_rework}}
  end

  # approve: apply the captured PatchSet to the integration target, then integrate. A conflict is an
  # honest failure (rolls back, suggest rework) — never a silent accept of unapplied work.
  defp apply_effect(slice, :approve, opts) do
    case apply_patch(slice, opts) do
      :ok ->
        updated = transition!(slice, :disposition_approve, opts)
        {:ok, %{slice: updated, terminal_state: :integrated}}

      {:error, reason} ->
        {:error, {:patch_conflict, reason}}
    end
  end

  # Injectable seam (`:apply_patch`) so tests run $0 without a real git target; production applies
  # the captured PatchSet via PatchSetApplicator. A slice with no captured PatchSet has nothing to
  # apply (the human override still records) — only a real conflict blocks the approve.
  defp apply_patch(slice, opts) do
    apply_fun = Keyword.get(opts, :apply_patch, &default_apply_patch/2)
    apply_fun.(slice, opts)
  end

  defp default_apply_patch(slice, opts) do
    case latest_patch_set(slice) do
      nil ->
        :ok

      patch_set ->
        case PatchSetApplicator.apply_patch_set(
               patch_set,
               Keyword.take(opts, [:blob_root, :station_run_id])
             ) do
          {:ok, _workspace} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # --- evidence + ledger -----------------------------------------------------

  defp record_approval!(slice, type, opts) do
    Ash.create!(
      HumanApproval,
      %{
        project_id: project_id!(slice),
        slice_id: slice.id,
        run_attempt_id: latest_run_attempt(slice.id) |> attempt_id(),
        approval_type: "triage_disposition",
        decision: decision(type),
        actor: Keyword.get(opts, :actor, "human"),
        rationale: Keyword.get(opts, :note)
      },
      domain: Factory
    )
  end

  defp write_event!(slice, type, key, approval, opts) do
    Ledger.write!(%{
      type: "triage.disposition",
      idempotency_key: key,
      project_id: project_id!(slice),
      slice_id: slice.id,
      payload: %{
        "disposition" => Atom.to_string(type),
        "decision" => Atom.to_string(decision(type)),
        "actor" => Keyword.get(opts, :actor, "human"),
        "note" => Keyword.get(opts, :note),
        "human_approval_id" => approval.id
      }
    })
  end

  defp decision(:approve), do: :approved
  defp decision(:rework), do: :reworked
  defp decision(:reject), do: :rejected

  defp transition!(slice, action, opts) do
    SliceLifecycle.transition!(slice, action,
      actor: Keyword.get(opts, :actor, "human"),
      reason: Keyword.get(opts, :note, "operator #{action}")
    )
  end

  # --- lookups ---------------------------------------------------------------

  defp idempotency_key(slice_id, type), do: "triage.disposition:#{slice_id}:#{type}"

  defp existing_event(key) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.idempotency_key == key))
  end

  defp slice!(id) do
    Slice
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "unknown slice_id #{inspect(id)}"
  end

  defp latest_run_attempt(slice_id) do
    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(& &1.attempt_no, :desc)
    |> List.first()
  end

  defp latest_patch_set(slice) do
    case latest_run_attempt(slice.id) do
      nil ->
        nil

      attempt ->
        PatchSet
        |> Ash.read!(domain: Factory)
        |> Enum.filter(&(&1.run_attempt_id == attempt.id))
        |> Enum.sort_by(&{DateTime.to_unix(&1.generated_at, :microsecond), &1.id}, :desc)
        |> List.first()
    end
  end

  defp attempt_id(nil), do: nil
  defp attempt_id(attempt), do: attempt.id

  defp project_id!(slice) do
    epic = Enum.find(Ash.read!(Epic, domain: Factory), &(&1.id == slice.epic_id))
    plan = epic && Enum.find(Ash.read!(Plan, domain: Factory), &(&1.id == epic.plan_id))
    plan && plan.project_id
  end
end
