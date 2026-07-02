defmodule Conveyor.Budget.ReservationGate do
  @moduledoc """
  a3hf.2.1.3: reserve-before-spend enforcement. Before an agent call spends, check the run's budget
  envelope and reserve — or refuse. Activates `budget_reservation@1` (`Conveyor.BudgetReservations`)
  against a `RunBudget`'s remaining token/cost envelope.

  This is the proactive complement to `Conveyor.Policy.RunBudgetGuard`, which records consumption
  *after* a spend and marks the budget exhausted. The gate refuses the *next* call once the envelope
  is gone, so an unattended run stops burning before the call rather than after it.

  Pure decision function: it reads the budget's fields (works on a `%RunBudget{}` or a plain map) and
  returns `{:ok, reservation}` or `{:deny, reason}`. Emitting ledger events / parking is the caller's
  job. An uncapped dimension (`nil` limit) is treated as unlimited.
  """

  alias Conveyor.BudgetReservations

  @type request :: %{optional(:tokens) => number(), optional(:cost) => number()}
  @type reason :: :budget_exhausted | :token_limit | :cost_limit | :concurrency_limit

  @doc """
  Reserve against `budget`'s remaining envelope. Denies when the budget is already exhausted, a
  capped dimension has no headroom left, or the request exceeds the remaining envelope.
  """
  @spec reserve(map(), request(), keyword()) :: {:ok, map()} | {:deny, reason()}
  def reserve(budget, request \\ %{}, opts \\ []) do
    cond do
      field(budget, :status) == :exhausted ->
        {:deny, :budget_exhausted}

      (dim = depleted_dimension(budget)) != nil ->
        {:deny, dim}

      true ->
        BudgetReservations.reserve(envelope(budget, opts), request, opts)
    end
  end

  @doc "Mark a reservation committed with the call's measured actuals."
  @spec commit(map(), map()) :: {:ok, map()}
  def commit(reservation, actuals), do: BudgetReservations.commit(reservation, actuals)

  # A capped dimension whose remaining envelope is <= 0 refuses the next call outright — even with
  # no per-call estimate — so a spent budget cannot spend again.
  defp depleted_dimension(budget) do
    cond do
      capped?(budget, :max_tokens) and remaining(budget, :max_tokens, :consumed_tokens) <= 0 ->
        :token_limit

      capped?(budget, :max_cost_cents) and
          remaining(budget, :max_cost_cents, :consumed_cost_cents) <= 0 ->
        :cost_limit

      true ->
        nil
    end
  end

  defp envelope(budget, opts) do
    BudgetReservations.envelope(
      scope_id: opts[:scope_id] || field(budget, :run_attempt_id) || "run-budget",
      token_limit: limit(budget, :max_tokens, :consumed_tokens),
      cost_limit: limit(budget, :max_cost_cents, :consumed_cost_cents),
      concurrency_limit: opts[:concurrency_limit] || 1,
      active_reservations: opts[:active_reservations] || 0
    )
  end

  # Remaining headroom for a dimension; an uncapped (nil) dimension is unlimited. `:infinity` sorts
  # above every number in Erlang term order, so `request > :infinity` is always false (never denies)
  # — i.e. unlimited.
  defp limit(budget, max_key, consumed_key) do
    if capped?(budget, max_key), do: remaining(budget, max_key, consumed_key), else: :infinity
  end

  defp remaining(budget, max_key, consumed_key),
    do: field(budget, max_key) - (field(budget, consumed_key) || 0)

  defp capped?(budget, max_key), do: is_integer(field(budget, max_key))

  defp field(budget, key), do: Map.get(budget, key)
end
