defmodule Conveyor.AuthorityEventsTest do
  use ExUnit.Case, async: true

  alias Conveyor.AuthorityEvents
  alias Conveyor.Factory
  alias Conveyor.Factory.AuthorityEvent

  test "Factory domain exposes AuthorityEvent with causal envelope fields" do
    resources = Factory |> Ash.Domain.Info.resources() |> MapSet.new()
    assert AuthorityEvent in resources

    attribute_names =
      AuthorityEvent
      |> Ash.Resource.Info.attributes()
      |> Enum.map(& &1.name)

    for attr <- [
          :event_id,
          :stream_id,
          :stream_version,
          :event_type,
          :subject_ref,
          :causation_id,
          :correlation_id,
          :trace_context,
          :payload_ref,
          :fencing_token,
          :policy_decision_id,
          :committed_at
        ] do
      assert attr in attribute_names
    end
  end

  test "AuthorityEvent converts to a CloudEvents-compatible envelope" do
    committed_at = ~U[2026-06-19 00:00:00.000000Z]

    event = %AuthorityEvent{
      event_id: "authority-event-001",
      stream_id: "station-run-001",
      stream_version: 3,
      event_type: "station.succeeded",
      subject_ref: %{"kind" => "station_run", "id_or_key" => "station-run-001"},
      correlation_id: "trace-001",
      trace_context: %{"trace_id" => "trace-001", "span_id" => "span-001"},
      payload_ref: %{"kind" => "ledger_event", "id_or_key" => "ledger-event-001"},
      fencing_token: "station-run-001:3",
      policy_decision_id: "policy-decision-001",
      committed_at: committed_at
    }

    assert AuthorityEvents.to_cloud_event(event) == %{
             "specversion" => "1.0",
             "id" => "authority-event-001",
             "source" => "/conveyor/authority/station-run-001",
             "type" => "station.succeeded",
             "subject" => "station_run:station-run-001",
             "time" => DateTime.to_iso8601(committed_at),
             "datacontenttype" => "application/json",
             "data" => %{
               "stream_id" => "station-run-001",
               "stream_version" => 3,
               "subject_ref" => %{"kind" => "station_run", "id_or_key" => "station-run-001"},
               "payload_ref" => %{"kind" => "ledger_event", "id_or_key" => "ledger-event-001"},
               "fencing_token" => "station-run-001:3",
               "policy_decision_id" => "policy-decision-001",
               "trace_context" => %{"trace_id" => "trace-001", "span_id" => "span-001"}
             }
           }
  end

  test "provider-safe trace context strips internal identifiers" do
    context = %{
      "trace_id" => "trace-001",
      "span_id" => "span-001",
      "run_attempt_id" => "internal-run-attempt",
      "station_run_id" => "internal-station-run",
      "correlation_id" => "correlation-001"
    }

    assert AuthorityEvents.provider_safe_trace_context(context) == %{
             "trace_id" => "trace-001",
             "span_id" => "span-001",
             "correlation_id" => "correlation-001"
           }
  end
end
