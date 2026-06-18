defmodule Conveyor.Policy.RunBudgetGuard do
  @moduledoc """
  Applies per-run budget caps and stops work on budget exhaustion.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBudget
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.Ledger
  alias Conveyor.Repo
  alias Conveyor.Sandbox.Runner

  defmodule Result do
    @moduledoc false

    @type status :: :active | :exhausted

    @type t :: %__MODULE__{
            status: status(),
            budget: RunBudget.t(),
            exceeded_cap: atom() | nil,
            finding: map() | nil,
            run_attempt: RunAttempt.t() | nil,
            slice: Slice.t() | nil,
            ledger_event: LedgerEvent.t() | nil
          }

    @enforce_keys [:status, :budget, :exceeded_cap, :finding, :run_attempt, :slice, :ledger_event]
    defstruct [:status, :budget, :exceeded_cap, :finding, :run_attempt, :slice, :ledger_event]
  end

  @spec record_tool_invocation!(
          String.t() | RunBudget.t(),
          ToolInvocation.t(),
          Runner.Result.t() | nil,
          keyword()
        ) ::
          Result.t()
  def record_tool_invocation!(budget_or_id, %ToolInvocation{} = invocation, execution, opts \\ []) do
    output_bytes = output_bytes(execution)

    record!(
      budget_or_id,
      %{
        tool_calls: 1,
        command_count: 1,
        output_bytes: output_bytes,
        reason: "tool invocation consumed run budget"
      },
      Keyword.put_new(opts, :run_attempt_id, invocation.run_attempt_id)
    )
  end

  @spec record!(String.t() | RunBudget.t(), map(), keyword()) :: Result.t()
  def record!(budget_id, measurements, opts) when is_binary(budget_id) do
    RunBudget
    |> get_by_id!(budget_id)
    |> record!(measurements, opts)
  end

  def record!(%RunBudget{} = budget, measurements, opts) when is_map(measurements) do
    context = context_for!(budget, opts)
    counters = counters(budget, measurements)
    exceeded_cap = exceeded_cap(budget, counters, measurements)
    finding = finding(exceeded_cap, counters, measurements)

    Repo.transaction(fn ->
      {updated_budget, budget_notifications} = update_budget!(budget, counters, exceeded_cap)

      {run_attempt, run_attempt_notifications} =
        maybe_stop_run_attempt(context.run_attempt, exceeded_cap)

      {slice, slice_notifications} = maybe_transition_slice(context.slice, exceeded_cap, opts)

      {ledger_event, ledger_notifications} =
        maybe_write_ledger_event!(context, updated_budget, exceeded_cap, finding)

      result = %Result{
        status: if(exceeded_cap, do: :exhausted, else: :active),
        budget: updated_budget,
        exceeded_cap: exceeded_cap,
        finding: finding,
        run_attempt: run_attempt,
        slice: slice,
        ledger_event: ledger_event
      }

      notifications =
        budget_notifications ++
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

  defp counters(budget, measurements) do
    %{
      tool_calls: budget.consumed_tool_calls + Map.get(measurements, :tool_calls, 0),
      command_count: budget.consumed_command_count + Map.get(measurements, :command_count, 0),
      output_bytes: budget.consumed_output_bytes + Map.get(measurements, :output_bytes, 0)
    }
  end

  defp exceeded_cap(budget, counters, measurements) do
    [
      {:max_tool_calls, budget.max_tool_calls, counters.tool_calls},
      {:max_command_count, budget.max_command_count, counters.command_count},
      {:max_output_bytes, budget.max_output_bytes, counters.output_bytes},
      {:max_repeated_command_count, budget.max_repeated_command_count,
       Map.get(measurements, :repeated_command_count, 0)},
      {:max_same_file_rewrites, budget.max_same_file_rewrites,
       Map.get(measurements, :same_file_rewrites, 0)},
      {:max_no_diff_progress_ms, budget.max_no_diff_progress_ms,
       Map.get(measurements, :no_diff_progress_ms, 0)},
      {:max_idle_ms, budget.max_idle_ms, Map.get(measurements, :idle_ms, 0)},
      {:max_wall_clock_ms, budget.max_wall_clock_ms, Map.get(measurements, :wall_clock_ms, 0)},
      {:max_tokens, budget.max_tokens, Map.get(measurements, :tokens, 0)},
      {:max_cost_cents, budget.max_cost_cents, Map.get(measurements, :cost_cents, 0)}
    ]
    |> Enum.find_value(fn
      {_cap, nil, _value} -> nil
      {cap, limit, value} when value > limit -> cap
      _within_cap -> nil
    end)
  end

  defp finding(nil, _counters, _measurements), do: nil

  defp finding(exceeded_cap, counters, measurements) do
    %{
      "severity" => "blocking",
      "category" => "budget",
      "message" => Map.get(measurements, :reason, "run budget exhausted"),
      "exceeded_cap" => Atom.to_string(exceeded_cap),
      "consumed" => %{
        "tool_calls" => counters.tool_calls,
        "command_count" => counters.command_count,
        "output_bytes" => counters.output_bytes,
        "repeated_command_count" => Map.get(measurements, :repeated_command_count, 0),
        "same_file_rewrites" => Map.get(measurements, :same_file_rewrites, 0),
        "no_diff_progress_ms" => Map.get(measurements, :no_diff_progress_ms, 0)
      }
    }
  end

  defp update_budget!(budget, counters, nil) do
    Ash.update!(
      budget,
      %{
        consumed_tool_calls: counters.tool_calls,
        consumed_command_count: counters.command_count,
        consumed_output_bytes: counters.output_bytes
      },
      domain: Factory,
      return_notifications?: true
    )
  end

  defp update_budget!(budget, counters, _exceeded_cap) do
    Ash.update!(
      budget,
      %{
        consumed_tool_calls: counters.tool_calls,
        consumed_command_count: counters.command_count,
        consumed_output_bytes: counters.output_bytes,
        status: :exhausted
      },
      domain: Factory,
      return_notifications?: true
    )
  end

  defp maybe_stop_run_attempt(run_attempt, nil), do: {run_attempt, []}

  defp maybe_stop_run_attempt(%RunAttempt{} = run_attempt, _exceeded_cap) do
    Ash.update!(
      run_attempt,
      %{
        status: :failed,
        outcome: :needs_rework,
        failure_category: "budget_exhausted",
        completed_at: DateTime.utc_now(:microsecond)
      },
      domain: Factory,
      return_notifications?: true
    )
  end

  defp maybe_transition_slice(slice, nil, _opts), do: {slice, []}

  defp maybe_transition_slice(%Slice{} = slice, _exceeded_cap, opts) do
    state = Keyword.get(opts, :slice_state, :needs_rework)
    Ash.update!(slice, %{state: state}, domain: Factory, return_notifications?: true)
  end

  defp maybe_write_ledger_event!(_context, _budget, nil, _finding), do: {nil, []}

  defp maybe_write_ledger_event!(context, budget, exceeded_cap, finding) do
    Ledger.write!(
      %{
        project_id: context.project.id,
        slice_id: context.slice && context.slice.id,
        run_attempt_id: context.run_attempt && context.run_attempt.id,
        idempotency_key: "budget_exhausted:#{budget.id}:#{exceeded_cap}",
        type: "budget.exhausted",
        payload: %{
          "run_budget_id" => budget.id,
          "exceeded_cap" => Atom.to_string(exceeded_cap),
          "finding" => finding
        }
      },
      return_notifications?: true
    )
  end

  defp context_for!(budget, opts) do
    run_attempt =
      maybe_get_by_id(RunAttempt, Keyword.get(opts, :run_attempt_id)) ||
        get_by_id!(RunAttempt, budget.run_attempt_id)

    slice =
      maybe_get_by_id(Slice, Keyword.get(opts, :slice_id)) ||
        get_by_id!(Slice, run_attempt.slice_id)

    project =
      maybe_get_by_id(Project, Keyword.get(opts, :project_id)) || project_for_slice!(slice)

    %{project: project, run_attempt: run_attempt, slice: slice}
  end

  defp project_for_slice!(slice) do
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    get_by_id!(Project, plan.project_id)
  end

  defp output_bytes(nil), do: 0

  defp output_bytes(%Runner.Result{} = execution),
    do: byte_size(execution.stdout <> execution.stderr)

  defp maybe_get_by_id(_resource, nil), do: nil
  defp maybe_get_by_id(resource, id), do: get_by_id!(resource, id)

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end
end
