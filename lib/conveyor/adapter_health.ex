defmodule Conveyor.AdapterHealth do
  @moduledoc """
  Adapter circuit health state.
  """

  @opening_failures MapSet.new([
                      :protocol_failure,
                      :transport_failure,
                      :capability_drift,
                      :invalid_event_sample,
                      :failed_cancellation_probe,
                      :provider_unavailable
                    ])

  def new(adapter),
    do: %{adapter: adapter, state: :closed, reason_codes: [], consecutive_failures: 0}

  def record_failure(state, :coding_quality_miss), do: state

  def record_failure(state, reason) do
    failures = state.consecutive_failures + 1
    reasons = Enum.uniq(state.reason_codes ++ [reason])

    state
    |> Map.put(:consecutive_failures, failures)
    |> Map.put(:reason_codes, reasons)
    |> maybe_open(reason, failures)
  end

  def admission_permit_status(%{state: :open}), do: :denied
  def admission_permit_status(_state), do: :allowed

  def ready_to_probe(%{state: :open} = state), do: %{state | state: :half_open}
  def ready_to_probe(state), do: state

  defp maybe_open(state, reason, failures) do
    if MapSet.member?(@opening_failures, reason) and failures >= 2 do
      %{state | state: :open}
    else
      state
    end
  end
end
