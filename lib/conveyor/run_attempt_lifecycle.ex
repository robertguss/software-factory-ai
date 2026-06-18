defmodule Conveyor.RunAttemptLifecycle do
  @moduledoc """
  Guarded RunAttempt lifecycle transitions and retry creation with ledger events.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Ledger
  alias Conveyor.Repo

  @spec transition!(struct(), atom(), keyword()) :: struct()
  def transition!(%RunAttempt{} = attempt, action, opts \\ []) when is_atom(action) do
    previous_status = attempt.status

    Repo.transaction(fn ->
      context = context_for!(attempt.slice_id)

      {updated_attempt, notifications} =
        Ash.update!(attempt, %{},
          action: action,
          domain: Factory,
          return_notifications?: true
        )

      {_event, ledger_notifications} =
        write_transition_event!(updated_attempt, previous_status, action, context.project, opts)

      {updated_attempt, notifications ++ ledger_notifications}
    end)
    |> notify_result()
  end

  @spec create_retry_attempt!(struct(), struct(), keyword()) :: struct()
  def create_retry_attempt!(%RunAttempt{} = failed_attempt, %RunSpec{} = run_spec, opts \\ []) do
    Repo.transaction(fn ->
      require_failed_attempt!(failed_attempt)
      require_fresh_run_spec!(failed_attempt, run_spec)
      context = context_for!(failed_attempt.slice_id)

      {retry_attempt, notifications} =
        Ash.create!(
          RunAttempt,
          %{
            slice_id: failed_attempt.slice_id,
            run_spec_id: run_spec.id,
            attempt_no: run_spec.attempt_no,
            base_commit: run_spec.base_commit,
            status: :planned,
            outcome: :none,
            orchestrator_version:
              Keyword.get(opts, :orchestrator_version, failed_attempt.orchestrator_version),
            trace_id: Keyword.get(opts, :trace_id, retry_trace_id(failed_attempt, run_spec))
          },
          domain: Factory,
          return_notifications?: true
        )

      {_event, ledger_notifications} =
        write_retry_event!(failed_attempt, retry_attempt, context.project, opts)

      {retry_attempt, notifications ++ ledger_notifications}
    end)
    |> notify_result()
  end

  defp notify_result({:ok, {record, notifications}}) do
    Ash.Notifier.notify(notifications)
    record
  end

  defp notify_result({:error, reason}), do: raise(reason)

  defp require_failed_attempt!(%RunAttempt{status: :failed}), do: :ok

  defp require_failed_attempt!(%RunAttempt{status: status}) do
    raise ArgumentError, "Retry attempts require a failed RunAttempt; got #{status}"
  end

  defp require_fresh_run_spec!(failed_attempt, run_spec) do
    expected_attempt_no = failed_attempt.attempt_no + 1

    cond do
      run_spec.slice_id != failed_attempt.slice_id ->
        raise ArgumentError, "Retry RunSpec must belong to the failed RunAttempt Slice"

      run_spec.id == failed_attempt.run_spec_id ->
        raise ArgumentError, "Retry RunSpec must be fresh"

      run_spec.attempt_no != expected_attempt_no ->
        raise ArgumentError,
              "Retry RunSpec attempt_no must be #{expected_attempt_no}; got #{run_spec.attempt_no}"

      true ->
        :ok
    end
  end

  defp context_for!(slice_id) do
    slice = get_by_id!(Slice, slice_id)
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    project = get_by_id!(Project, plan.project_id)

    %{slice: slice, epic: epic, plan: plan, project: project}
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp write_transition_event!(attempt, previous_status, action, project, opts) do
    occurred_at = Keyword.get_lazy(opts, :occurred_at, fn -> DateTime.utc_now(:microsecond) end)
    actor = Keyword.get(opts, :actor, "system")
    reason = Keyword.get(opts, :reason, "run attempt transition")

    Ledger.write!(
      %{
        project_id: project.id,
        slice_id: attempt.slice_id,
        run_attempt_id: attempt.id,
        idempotency_key:
          idempotency_key(attempt.id, previous_status, attempt.status, occurred_at),
        type: "run_attempt.transitioned",
        payload: %{
          "actor" => actor,
          "run_attempt_id" => attempt.id,
          "slice_id" => attempt.slice_id,
          "action" => Atom.to_string(action),
          "previous_status" => Atom.to_string(previous_status),
          "status" => Atom.to_string(attempt.status),
          "reason" => reason
        },
        occurred_at: occurred_at
      },
      return_notifications?: true
    )
  end

  defp write_retry_event!(failed_attempt, retry_attempt, project, opts) do
    occurred_at = Keyword.get_lazy(opts, :occurred_at, fn -> DateTime.utc_now(:microsecond) end)
    actor = Keyword.get(opts, :actor, "system")
    reason = Keyword.get(opts, :reason, "run attempt retry")

    Ledger.write!(
      %{
        project_id: project.id,
        slice_id: retry_attempt.slice_id,
        run_attempt_id: retry_attempt.id,
        idempotency_key: retry_idempotency_key(failed_attempt.id, retry_attempt.id, occurred_at),
        type: "run_attempt.retry_created",
        payload: %{
          "actor" => actor,
          "previous_run_attempt_id" => failed_attempt.id,
          "run_attempt_id" => retry_attempt.id,
          "slice_id" => retry_attempt.slice_id,
          "previous_attempt_no" => failed_attempt.attempt_no,
          "attempt_no" => retry_attempt.attempt_no,
          "run_spec_id" => retry_attempt.run_spec_id,
          "reason" => reason
        },
        occurred_at: occurred_at
      },
      return_notifications?: true
    )
  end

  defp retry_trace_id(failed_attempt, run_spec) do
    "#{failed_attempt.trace_id}:retry:#{run_spec.attempt_no}"
  end

  defp idempotency_key(attempt_id, previous_status, status, occurred_at) do
    timestamp = DateTime.to_unix(occurred_at, :microsecond)
    "run_attempt:#{attempt_id}:#{previous_status}:#{status}:#{timestamp}"
  end

  defp retry_idempotency_key(failed_attempt_id, retry_attempt_id, occurred_at) do
    timestamp = DateTime.to_unix(occurred_at, :microsecond)
    "run_attempt_retry:#{failed_attempt_id}:#{retry_attempt_id}:#{timestamp}"
  end
end
