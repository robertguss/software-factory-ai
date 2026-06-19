defmodule Conveyor.BudgetReservations do
  @moduledoc """
  Budget envelope and reservation helpers.
  """

  def envelope(opts) do
    %{
      scope_id: Keyword.fetch!(opts, :scope_id),
      token_limit: Keyword.fetch!(opts, :token_limit),
      cost_limit: Keyword.fetch!(opts, :cost_limit),
      concurrency_limit: Keyword.fetch!(opts, :concurrency_limit),
      active_reservations: Keyword.get(opts, :active_reservations, 0)
    }
  end

  def reserve(envelope, request, opts \\ []) do
    cond do
      Map.get(request, :tokens, 0) > envelope.token_limit ->
        {:deny, :token_limit}

      Map.get(request, :cost, 0.0) > envelope.cost_limit ->
        {:deny, :cost_limit}

      envelope.active_reservations >= envelope.concurrency_limit ->
        {:deny, :concurrency_limit}

      true ->
        {:ok,
         %{
           envelope: envelope,
           requested: request,
           status: :reserved,
           trace_id: Keyword.get(opts, :trace_id),
           reserved_at: Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
         }}
    end
  end

  def commit(%{status: :reserved} = reservation, actuals) do
    {:ok, reservation |> Map.put(:status, :committed) |> Map.put(:committed_actuals, actuals)}
  end

  def before_spend(nil), do: {:deny, :reservation_required}
  def before_spend(%{status: :reserved}), do: :ok
  def before_spend(%{status: :committed}), do: :ok
  def before_spend(_reservation), do: {:deny, :reservation_required}
end
