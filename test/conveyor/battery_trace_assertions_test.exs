defmodule Conveyor.BatteryTraceAssertionsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Battery.TraceAssertions

  test "never fails when any canonical event matches the forbidden predicate" do
    assertions = [
      %{
        "assertion_id" => "never_hidden_oracle",
        "operator" => "never",
        "source" => "event",
        "match" => %{"field" => "event_type", "equals" => "oracle.hidden_read"}
      }
    ]

    trace = %{
      events: [
        %{"event_id" => "event-1", "event_type" => "station.started"},
        %{"event_id" => "event-2", "event_type" => "oracle.hidden_read"}
      ],
      effect_receipts: []
    }

    assert [
             %{
               assertion_id: "never_hidden_oracle",
               result: :failed,
               observed_count: 1,
               matching_record_ids: ["event-2"],
               failure_reason: :forbidden_match_observed
             }
           ] = TraceAssertions.evaluate(assertions, trace)
  end

  test "eventually passes when an effect receipt matches the required predicate" do
    assertions = [
      %{
        "assertion_id" => "effect_eventually_confirmed",
        "operator" => "eventually",
        "source" => "effect_receipt",
        "match" => %{"field" => "reconciliation_status", "equals" => "confirmed"}
      }
    ]

    trace = %{
      events: [],
      effect_receipts: [
        %{"idempotency_key" => "effect-1", "reconciliation_status" => "pending"},
        %{"idempotency_key" => "effect-2", "reconciliation_status" => "confirmed"}
      ]
    }

    assert [
             %{
               assertion_id: "effect_eventually_confirmed",
               result: :passed,
               observed_count: 1,
               matching_record_ids: ["effect-2"],
               failure_reason: nil
             }
           ] = TraceAssertions.evaluate(assertions, trace)
  end

  test "always fails when any canonical event violates the predicate" do
    assertions = [
      %{
        "assertion_id" => "all_events_keep_trace",
        "operator" => "always",
        "source" => "event",
        "match" => %{"field" => "trace_context.trace_id", "equals" => "trace-1"}
      }
    ]

    trace = %{
      events: [
        %{
          "event_id" => "event-1",
          "event_type" => "station.started",
          "trace_context" => %{"trace_id" => "trace-1"}
        },
        %{
          "event_id" => "event-2",
          "event_type" => "station.succeeded",
          "trace_context" => %{"trace_id" => "trace-other"}
        }
      ],
      effect_receipts: []
    }

    assert [
             %{
               assertion_id: "all_events_keep_trace",
               result: :failed,
               observed_count: 1,
               matching_record_ids: ["event-1"],
               failure_reason: :not_all_records_matched
             }
           ] = TraceAssertions.evaluate(assertions, trace)
  end

  test "bounded_count fails when matching events exceed the declared maximum" do
    assertions = [
      %{
        "assertion_id" => "at_most_one_policy_block",
        "operator" => "bounded_count",
        "source" => "event",
        "match" => %{"field" => "event_type", "equals" => "policy.blocked"},
        "min_count" => 0,
        "max_count" => 1
      }
    ]

    trace = %{
      events: [
        %{"event_id" => "event-1", "event_type" => "policy.blocked"},
        %{"event_id" => "event-2", "event_type" => "station.recovered"},
        %{"event_id" => "event-3", "event_type" => "policy.blocked"}
      ],
      effect_receipts: []
    }

    assert [
             %{
               assertion_id: "at_most_one_policy_block",
               result: :failed,
               observed_count: 2,
               matching_record_ids: ["event-1", "event-3"],
               failure_reason: :count_out_of_bounds
             }
           ] = TraceAssertions.evaluate(assertions, trace)
  end
end
