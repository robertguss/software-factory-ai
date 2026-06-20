defmodule Conveyor.AttemptLoop do
  @moduledoc """
  Width-1 multi-attempt conductor for a single Slice.
  """

  alias Conveyor.AttemptBudget
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer
  alias Conveyor.Jobs.RunGate
  alias Conveyor.Ledger
  alias Conveyor.Recovery.ReworkSynthesizer
  alias Conveyor.RunAttemptLifecycle
  alias Conveyor.RunSlice
  alias Conveyor.RunSpecForge
  alias Conveyor.SliceLifecycle

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            status: atom(),
            attempts: [struct()],
            events: [map()],
            report: map()
          }

    @enforce_keys [:status, :attempts, :events, :report]
    defstruct [:status, :attempts, :events, :report]
  end

  @terminal_outcomes [:accepted, :policy_blocked, :rejected]

  @spec run_to_done!(RunAttempt.t() | Ecto.UUID.t(), keyword()) :: Result.t()
  def run_to_done!(run_attempt_or_id, opts \\ []) do
    attempt = run_attempt!(run_attempt_or_id)
    budget = AttemptBudget.new(opts)
    loop(attempt, budget, [], [], opts)
  end

  defp loop(%RunAttempt{} = attempt, budget, attempts, events, opts) do
    run_spec = get_by_id!(RunSpec, attempt.run_spec_id)
    slice_result = run_slice!(attempt, opts)
    gate = run_gate!(run_spec, attempt, slice_result, opts)
    finalization = finalize_gate!(gate, run_spec, attempt, opts)
    final_attempt = final_attempt(finalization, attempt)
    attempt_event = attempt_event(final_attempt, gate)
    attempts = attempts ++ [final_attempt]
    events = events ++ [attempt_event]

    cond do
      final_attempt.outcome in @terminal_outcomes ->
        result(final_attempt.outcome, attempts, events)

      final_attempt.outcome == :needs_rework and
          AttemptBudget.retry_allowed?(budget, length(attempts)) ->
        retry_attempt = prepare_retry!(final_attempt, run_spec, gate, budget, attempts, opts)
        rung = AttemptBudget.rung_for_retry(budget, retry_attempt.attempt_no)
        event = escalation_event!(final_attempt, retry_attempt, gate, rung, opts)
        loop(retry_attempt, budget, attempts, events ++ [escalation_event(event)], opts)

      final_attempt.outcome == :needs_rework ->
        result(:attempt_budget_exhausted, attempts, events)

      true ->
        result(:failed, attempts, events)
    end
  end

  defp result(status, attempts, events) do
    %Result{
      status: status,
      attempts: attempts,
      events: events,
      report: %{
        "schema_version" => "conveyor.attempt_loop@1",
        "status" => Atom.to_string(status),
        "attempt_count" => length(attempts),
        "rework_recovered" =>
          status == :accepted and Enum.any?(events, &Map.has_key?(&1, "rung")),
        "rework_feedback_categories" =>
          events
          |> Enum.flat_map(&List.wrap(&1["finding_categories"]))
          |> Enum.uniq()
          |> Enum.sort()
      }
    }
  end

  defp prepare_retry!(final_attempt, run_spec, gate, budget, attempts, opts) do
    actor = Keyword.get(opts, :actor, "attempt-loop")
    final_attempt |> slice_for_attempt!() |> synthesize_rework!(gate, actor)
    mark_ready!(final_attempt, actor)

    rung = AttemptBudget.rung_for_retry(budget, length(attempts) + 1)
    retry_spec = forge_retry_run_spec!(final_attempt, run_spec, rung, opts)

    create_retry_attempt!(final_attempt, retry_spec, opts)
  end

  defp synthesize_rework!(slice, gate, actor) do
    ReworkSynthesizer.synthesize(slice, gate, actor: actor)
  end

  defp mark_ready!(final_attempt, actor) do
    final_attempt
    |> slice_for_attempt!()
    |> SliceLifecycle.transition!(:mark_ready,
      actor: actor,
      reason: "trusted gate findings synthesized for rework"
    )
  end

  defp forge_retry_run_spec!(final_attempt, run_spec, rung, opts) do
    case Keyword.get(opts, :forge_run_spec) do
      fun when is_function(fun, 3) -> fun.(final_attempt, run_spec, rung)
      nil -> RunSpecForge.forge_retry!(final_attempt, run_spec, rung: rung)
    end
  end

  defp create_retry_attempt!(final_attempt, retry_spec, opts) do
    case Keyword.get(opts, :create_retry_attempt) do
      fun when is_function(fun, 2) ->
        fun.(final_attempt, retry_spec)

      nil ->
        RunAttemptLifecycle.create_retry_attempt!(final_attempt, retry_spec,
          actor: Keyword.get(opts, :actor, "attempt-loop"),
          reason: "retry gate rework"
        )
    end
  end

  defp run_slice!(attempt, opts) do
    case Keyword.get(opts, :run_slice) do
      fun when is_function(fun, 1) -> fun.(attempt)
      nil -> RunSlice.run!(attempt, Keyword.take(opts, [:actor, :blob_root]))
    end
  end

  defp run_gate!(run_spec, attempt, slice_result, opts) do
    case Keyword.get(opts, :run_gate) do
      fun when is_function(fun, 3) ->
        fun.(run_spec, attempt, slice_result)

      nil ->
        RunGate.run_gate_only!(
          %{
            run_attempt_id: attempt.id,
            run_spec: run_spec,
            verification_result: slice_result.output["verification_result"]
          },
          Keyword.get(opts, :gate_stages, [Conveyor.Gate.Stages.TestExecution]),
          gate_code_sha256: Keyword.get(opts, :gate_code_sha256, digest("gate")),
          policy_sha256: run_spec.policy_sha256,
          contract_lock_sha256: run_spec.contract_lock_sha256
        )
    end
  end

  defp finalize_gate!(gate, run_spec, attempt, opts) do
    case Keyword.get(opts, :finalize_gate) do
      fun when is_function(fun, 3) ->
        fun.(gate, run_spec, attempt)

      nil ->
        Finalizer.finalize!(
          gate,
          %{run_attempt: attempt, run_spec: run_spec},
          actor: Keyword.get(opts, :actor, "attempt-loop")
        )
    end
  end

  defp final_attempt(finalization, fallback) do
    case value(finalization, :run_attempt) do
      %RunAttempt{} = run_attempt -> run_attempt
      _missing -> get_by_id!(RunAttempt, fallback.id)
    end
  end

  defp attempt_event(%RunAttempt{} = attempt, %Gate.Result{} = gate) do
    %{
      "attempt_no" => attempt.attempt_no,
      "outcome" => Atom.to_string(attempt.outcome),
      "status" => Atom.to_string(attempt.status),
      "finding_categories" => finding_categories(gate)
    }
  end

  defp escalation_event!(prior_attempt, retry_attempt, gate, rung, opts) do
    project = project_for_attempt!(retry_attempt)
    actor = Keyword.get(opts, :actor, "attempt-loop")
    rung_name = Map.fetch!(rung, "rung")

    Ledger.write!(%{
      project_id: project.id,
      slice_id: retry_attempt.slice_id,
      run_attempt_id: retry_attempt.id,
      idempotency_key: "attempt_escalated:#{prior_attempt.id}:#{retry_attempt.id}:#{rung_name}",
      type: "attempt.escalated",
      payload: %{
        "actor" => actor,
        "previous_run_attempt_id" => prior_attempt.id,
        "run_attempt_id" => retry_attempt.id,
        "attempt_no" => retry_attempt.attempt_no,
        "rung" => rung_name,
        "finding_categories" => finding_categories(gate),
        "previous_outcome" => Atom.to_string(prior_attempt.outcome)
      }
    })
  end

  defp escalation_event(%LedgerEvent{} = event) do
    %{
      "attempt_no" => event.payload["attempt_no"],
      "rung" => event.payload["rung"],
      "finding_categories" => event.payload["finding_categories"]
    }
  end

  defp finding_categories(%Gate.Result{} = gate) do
    gate.findings
    |> Enum.map(&(&1["category"] || &1[:category]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp run_attempt!(%RunAttempt{} = attempt), do: attempt
  defp run_attempt!(id), do: get_by_id!(RunAttempt, id)

  defp slice_for_attempt!(%RunAttempt{} = attempt), do: get_by_id!(Slice, attempt.slice_id)

  defp project_for_attempt!(%RunAttempt{} = attempt) do
    slice = get_by_id!(Slice, attempt.slice_id)
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    get_by_id!(Project, plan.project_id)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
