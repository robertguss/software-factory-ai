defmodule Conveyor.Effects.Attempts do
  @moduledoc """
  Helpers for effect attempt/receipt retry safety.
  """

  alias Conveyor.Factory.EffectReceipt

  @blocking_statuses [:pending, :ambiguous]

  @spec ensure_retry_allowed!([EffectReceipt.t()]) :: :ok
  def ensure_retry_allowed!(receipts) when is_list(receipts) do
    blocking =
      Enum.filter(receipts, fn receipt ->
        receipt.reconciliation_status in @blocking_statuses
      end)

    case blocking do
      [] ->
        :ok

      receipts ->
        keys =
          receipts
          |> Enum.map(& &1.idempotency_key)
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        raise ArgumentError,
              "reconcile pending or ambiguous effect receipts before retry: #{keys}"
    end
  end

  @spec attempt_idempotency_key(Ecto.UUID.t() | String.t(), Ecto.UUID.t() | String.t()) ::
          String.t()
  def attempt_idempotency_key(station_run_id, station_effect_id) do
    "effect-attempt:#{station_run_id}:#{station_effect_id}"
  end
end
