defmodule Conveyor.EffectAttemptReceiptTest do
  use ExUnit.Case, async: true

  alias Conveyor.Effects.Attempts
  alias Conveyor.Factory
  alias Conveyor.Factory.EffectAttempt
  alias Conveyor.Factory.EffectReceipt

  test "Factory domain exposes EffectAttempt and EffectReceipt resources" do
    resources = Factory |> Ash.Domain.Info.resources() |> MapSet.new()

    assert EffectAttempt in resources
    assert EffectReceipt in resources
  end

  test "effect resources expose the split attempt and receipt fields" do
    assert_attrs(EffectAttempt, [
      :station_run_id,
      :station_effect_id,
      :fencing_token,
      :admission_permit_id,
      :idempotency_key,
      :request_digest,
      :started_at,
      :completed_at,
      :status
    ])

    assert_attrs(EffectReceipt, [
      :effect_attempt_id,
      :fencing_token,
      :idempotency_key,
      :external_correlation_id,
      :request_digest,
      :result_digest,
      :reconciliation_status,
      :trace_id,
      :observed_at
    ])
  end

  test "pending or ambiguous receipts block retry until reconciliation runs first" do
    confirmed = %EffectReceipt{reconciliation_status: :confirmed}
    pending = %EffectReceipt{reconciliation_status: :pending, idempotency_key: "effect:pending"}

    ambiguous = %EffectReceipt{
      reconciliation_status: :ambiguous,
      idempotency_key: "effect:ambiguous"
    }

    assert :ok = Attempts.ensure_retry_allowed!([])
    assert :ok = Attempts.ensure_retry_allowed!([confirmed])

    assert_raise ArgumentError,
                 ~r/reconcile pending or ambiguous effect receipts before retry/,
                 fn ->
                   Attempts.ensure_retry_allowed!([confirmed, pending])
                 end

    assert_raise ArgumentError, ~r/effect:ambiguous/, fn ->
      Attempts.ensure_retry_allowed!([ambiguous])
    end
  end

  defp assert_attrs(resource, expected_attrs) do
    attribute_names =
      resource
      |> Ash.Resource.Info.attributes()
      |> Enum.map(& &1.name)

    for attr <- expected_attrs do
      assert attr in attribute_names
    end
  end
end
