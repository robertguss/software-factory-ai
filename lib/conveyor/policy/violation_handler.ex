defmodule Conveyor.Policy.ViolationHandler do
  @moduledoc """
  Records policy violations and stops affected work.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.Ledger
  alias Conveyor.Policy.Engine
  alias Conveyor.Repo

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            incident: Incident.t(),
            run_attempt: RunAttempt.t() | nil,
            slice: Slice.t() | nil,
            ledger_event: struct()
          }

    @enforce_keys [:incident, :run_attempt, :slice, :ledger_event]
    defstruct [:incident, :run_attempt, :slice, :ledger_event]
  end

  @spec record!(Engine.Decision.t(), ToolInvocation.t(), keyword()) :: Result.t()
  def record!(%Engine.Decision{status: :blocked} = decision, %ToolInvocation{} = invocation, opts) do
    context = context_for!(invocation, opts)
    severity = Keyword.get(opts, :policy_violation_severity, :error)
    occurred_at = Keyword.get_lazy(opts, :occurred_at, fn -> DateTime.utc_now(:microsecond) end)

    Repo.transaction(fn ->
      {incident, incident_notifications} =
        create_incident!(context, invocation, decision, severity)

      {run_attempt, run_attempt_notifications} =
        stop_run_attempt(context.run_attempt, occurred_at)

      {slice, slice_notifications} = transition_slice(context.slice, severity)

      {ledger_event, ledger_notifications} =
        write_ledger_event!(context, invocation, incident, decision, severity, occurred_at)

      result = %Result{
        incident: incident,
        run_attempt: run_attempt,
        slice: slice,
        ledger_event: ledger_event
      }

      notifications =
        incident_notifications ++
          run_attempt_notifications ++ slice_notifications ++ ledger_notifications

      {result, notifications}
    end)
    |> case do
      {:ok, {result, notifications}} ->
        Ash.Notifier.notify(notifications)
        result

      {:error, reason} ->
        raise reason
    end
  end

  defp context_for!(invocation, opts) do
    run_attempt = maybe_get_by_id(RunAttempt, invocation.run_attempt_id)

    slice =
      maybe_get_by_id(Slice, Keyword.get(opts, :slice_id) || slice_id(invocation, run_attempt))

    project =
      maybe_get_by_id(Project, Keyword.get(opts, :project_id)) || project_for_slice!(slice)

    %{project: project, run_attempt: run_attempt, slice: slice}
  end

  defp slice_id(_invocation, %RunAttempt{} = run_attempt), do: run_attempt.slice_id
  defp slice_id(_invocation, nil), do: nil

  defp project_for_slice!(%Slice{} = slice) do
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    get_by_id!(Project, plan.project_id)
  end

  defp project_for_slice!(nil) do
    raise ArgumentError, "policy violations require project context"
  end

  defp create_incident!(context, invocation, decision, severity) do
    Ash.create!(
      Incident,
      %{
        project_id: context.project.id,
        slice_id: context.slice && context.slice.id,
        run_attempt_id: context.run_attempt && context.run_attempt.id,
        severity: severity,
        category: "policy_violation",
        description: decision.message,
        evidence_refs: [tool_invocation_ref(invocation)]
      },
      domain: Factory,
      return_notifications?: true
    )
  end

  defp stop_run_attempt(nil, _occurred_at), do: {nil, []}

  defp stop_run_attempt(%RunAttempt{} = run_attempt, occurred_at) do
    Ash.update!(
      run_attempt,
      %{
        status: :failed,
        outcome: :policy_blocked,
        failure_category: "policy_violation",
        completed_at: occurred_at
      },
      domain: Factory,
      return_notifications?: true
    )
  end

  defp transition_slice(nil, _severity), do: {nil, []}

  defp transition_slice(%Slice{} = slice, :critical) do
    Ash.update!(slice, %{state: :failed}, domain: Factory, return_notifications?: true)
  end

  defp transition_slice(%Slice{} = slice, _severity) do
    Ash.update!(slice, %{state: :policy_blocked},
      domain: Factory,
      return_notifications?: true
    )
  end

  defp write_ledger_event!(context, invocation, incident, decision, severity, occurred_at) do
    Ledger.write!(
      %{
        project_id: context.project.id,
        slice_id: context.slice && context.slice.id,
        run_attempt_id: context.run_attempt && context.run_attempt.id,
        station_run_id: invocation.station_run_id,
        idempotency_key: "policy_blocked:#{invocation.id}",
        type: "policy.blocked",
        payload: %{
          "incident_id" => incident.id,
          "tool_invocation_id" => invocation.id,
          "policy_profile" => invocation.policy_profile,
          "decision_reason" => Atom.to_string(decision.reason),
          "severity" => Atom.to_string(severity),
          "command" => decision.command
        },
        occurred_at: occurred_at
      },
      return_notifications?: true
    )
  end

  defp tool_invocation_ref(invocation), do: "tool-invocations/#{invocation.id}"

  defp maybe_get_by_id(_resource, nil), do: nil
  defp maybe_get_by_id(resource, id), do: get_by_id!(resource, id)

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end
end
