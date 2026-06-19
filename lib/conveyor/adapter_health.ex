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

  def new(adapter, opts \\ []) do
    %{
      adapter: adapter,
      capability_snapshot_digest: Keyword.get(opts, :capability_snapshot_digest),
      state: :closed,
      reason_codes: [],
      consecutive_failures: 0,
      affected_grant_ids: Keyword.get(opts, :affected_grant_ids, [])
    }
  end

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

  def eligible_for_attempt?(%{state: :open}), do: false
  def eligible_for_attempt?(_state), do: true

  def ready_to_probe(%{state: :open} = state), do: %{state | state: :half_open}
  def ready_to_probe(state), do: state

  def record_capability_drift(state, opts) do
    detected_at = Keyword.get(opts, :detected_at)
    affected_grant_ids = Keyword.get(opts, :affected_grant_ids, state.affected_grant_ids || [])
    observed_digest = Keyword.fetch!(opts, :observed_capability_snapshot_digest)

    opened =
      state
      |> Map.put(:state, :open)
      |> Map.put(:reason_codes, Enum.uniq(state.reason_codes ++ [:capability_drift]))
      |> Map.put(:consecutive_failures, state.consecutive_failures + 1)
      |> Map.put(:affected_grant_ids, affected_grant_ids)
      |> Map.put(:opened_at, detected_at)
      |> Map.put(:output_fence, %{
        "artifact_ref" => Keyword.get(opts, :output_ref),
        "reason" => "capability_drift"
      })

    {opened, qualification_impact(opened, observed_digest, detected_at)}
  end

  def record_transient_outage(state, opts) do
    reason = Keyword.get(opts, :reason, :provider_unavailable)

    state
    |> Map.put(:state, :open)
    |> Map.put(:reason_codes, Enum.uniq(state.reason_codes ++ [reason]))
    |> Map.put(:consecutive_failures, state.consecutive_failures + 1)
    |> Map.put(:next_probe_at, Keyword.get(opts, :next_probe_at))
  end

  defp maybe_open(state, reason, failures) do
    if MapSet.member?(@opening_failures, reason) and failures >= 2 do
      %{state | state: :open}
    else
      state
    end
  end

  defp qualification_impact(state, observed_digest, detected_at) do
    %{
      "schema_version" => "conveyor.qualification_impact@1",
      "adapter" => state.adapter,
      "reason" => "capability_drift",
      "previous_capability_snapshot_digest" => state.capability_snapshot_digest,
      "observed_capability_snapshot_digest" => observed_digest,
      "affected_grant_ids" => state.affected_grant_ids,
      "suspend_new_permits" => true,
      "detected_at" => detected_at
    }
  end
end
