defmodule Conveyor.AdapterHealthIntegrationTest do
  use ExUnit.Case, async: true

  alias Conveyor.AdapterHealth

  @snapshot "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @observed "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  @detected_at "2026-06-19T00:00:00Z"

  test "an open circuit is ineligible for new attempts and permits" do
    opened =
      "primary-live"
      |> AdapterHealth.new(capability_snapshot_digest: @snapshot)
      |> AdapterHealth.record_failure(:transport_failure)
      |> AdapterHealth.record_failure(:protocol_failure)

    refute AdapterHealth.eligible_for_attempt?(opened)
    assert AdapterHealth.admission_permit_status(opened) == :denied
  end

  test "capability drift fences adapter output and emits a QualificationImpact projection" do
    state = AdapterHealth.new("primary-live", capability_snapshot_digest: @snapshot)

    assert {opened, impact} =
             AdapterHealth.record_capability_drift(state,
               observed_capability_snapshot_digest: @observed,
               output_ref: "artifact://adapter/output-1",
               affected_grant_ids: ["grant-1"],
               detected_at: @detected_at
             )

    assert opened.state == :open
    assert opened.capability_snapshot_digest == @snapshot
    assert opened.affected_grant_ids == ["grant-1"]
    assert opened.output_fence["artifact_ref"] == "artifact://adapter/output-1"
    assert opened.output_fence["reason"] == "capability_drift"

    assert impact["schema_version"] == "conveyor.qualification_impact@1"
    assert impact["reason"] == "capability_drift"
    assert impact["adapter"] == "primary-live"
    assert impact["previous_capability_snapshot_digest"] == @snapshot
    assert impact["observed_capability_snapshot_digest"] == @observed
    assert impact["affected_grant_ids"] == ["grant-1"]
    assert impact["suspend_new_permits"] == true
  end

  test "transient outage suspends execution without rewriting historical capability evidence" do
    state = AdapterHealth.new("primary-live", capability_snapshot_digest: @snapshot)

    suspended =
      AdapterHealth.record_transient_outage(state,
        reason: :provider_unavailable,
        next_probe_at: "2026-06-19T00:05:00Z"
      )

    assert suspended.state == :open
    assert suspended.capability_snapshot_digest == @snapshot
    assert suspended.reason_codes == [:provider_unavailable]
    assert suspended.next_probe_at == "2026-06-19T00:05:00Z"
    refute Map.has_key?(suspended, :output_fence)
  end
end
