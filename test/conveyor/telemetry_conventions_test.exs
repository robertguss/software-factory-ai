defmodule Conveyor.TelemetryConventionsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Telemetry.Conventions

  test "defines the required Phase 1 span hierarchy" do
    assert Conventions.required_span_hierarchy() == [
             {:run_slice,
              [
                :station_readiness,
                :station_baseline,
                :station_scout,
                :station_prompt,
                {:station_implement, [:adapter_pi_session, :tool_command]},
                :station_evidence,
                :station_review,
                :station_gate,
                :station_canary,
                :station_post_integration
              ]}
           ]

    assert Conventions.span_name(:run_slice) == "conveyor.run_slice"
    assert Conventions.span_name(:station_implement) == "conveyor.station.implement"
    assert Conventions.span_name(:adapter_pi_session) == "conveyor.adapter.pi.session"
    assert Conventions.span_name(:tool_command) == "conveyor.tool.command"
    assert Conventions.child_span?(:run_slice, :station_readiness)
    assert Conventions.child_span?(:station_implement, :adapter_pi_session)
    assert Conventions.child_span?(:station_implement, :tool_command)
    refute Conventions.child_span?(:adapter_pi_session, :tool_command)
  end

  test "attaches the same trace context to persisted records and projected artifacts" do
    context =
      Conventions.trace_context(
        "0123456789abcdef0123456789abcdef",
        "0123456789abcdef"
      )

    assert context.traceparent == "00-0123456789abcdef0123456789abcdef-0123456789abcdef-01"

    for subject <- Conventions.required_trace_subjects() do
      record = Conventions.attach_trace_context(%{subject: subject}, context)

      assert record.trace_id == context.trace_id
      assert record.span_id == context.span_id
    end
  end

  test "allows only bounded metric dimensions" do
    assert Conventions.allowed_metric_dimensions() == [
             "adapter",
             "archetype",
             "eval_case",
             "eval_suite",
             "failure_category",
             "policy_profile",
             "profile",
             "project_id",
             "station",
             "status",
             "suite_kind"
           ]

    assert :ok =
             Conventions.validate_metric_dimensions(%{
               project_id: "project-1",
               station: "gate",
               adapter: "pi",
               profile: "verify",
               status: "passed",
               failure_category: "none",
               policy_profile: "verify",
               suite_kind: "acceptance_locked"
             })

    assert {:error, {:disallowed_metric_dimensions, ["command", "path", "prompt_text"]}} =
             Conventions.validate_metric_dimensions(%{
               project_id: "project-1",
               command: "mix test",
               path: "lib/conveyor.ex",
               prompt_text: "raw prompt"
             })
  end

  test "metric emission rejects high-cardinality labels before telemetry executes" do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:conveyor, :test, :metric],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:metric, event_name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok =
             Conveyor.Telemetry.emit_metric(
               [:conveyor, :test, :metric],
               %{duration_ms: 12},
               %{project_id: "project-1", station: "gate", status: "passed"}
             )

    assert_receive {:metric, [:conveyor, :test, :metric], %{duration_ms: 12},
                    %{project_id: "project-1", station: "gate", status: "passed"}}

    assert {:error, {:disallowed_metric_dimensions, ["error_message"]}} =
             Conveyor.Telemetry.emit_metric(
               [:conveyor, :test, :metric],
               %{duration_ms: 12},
               %{project_id: "project-1", error_message: "raw failure text"}
             )

    refute_receive {:metric, [:conveyor, :test, :metric], %{duration_ms: 12}, _}
  end
end
