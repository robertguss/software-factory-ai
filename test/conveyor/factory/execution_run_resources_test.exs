defmodule Conveyor.Factory.ExecutionRunResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationEffect
  alias Conveyor.Factory.StationRun
  alias Conveyor.RunAttemptLifecycle

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Execution sample", local_path: "/tmp/execution-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Execution plan",
          intent: "Run one slice attempt.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Execution epic", description: "Run attempts."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Execution slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, "run-spec-1", 1), domain: Factory)

    %{run_spec: run_spec, slice: slice}
  end

  test "run attempts enforce attempt number and retry from a fresh run spec", %{
    run_spec: run_spec,
    slice: slice
  } do
    attempt =
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 1), domain: Factory)

    assert attempt.status == :planned

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 1), domain: Factory)
    end

    assert_raise Ash.Error.Unknown, fn ->
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 2), domain: Factory)
    end

    failed =
      attempt
      |> RunAttemptLifecycle.transition!(:start, actor: "runner")
      |> RunAttemptLifecycle.transition!(:fail, actor: "runner", reason: "test failure")

    assert failed.status == :failed

    retry_run_spec =
      Ash.create!(RunSpec, run_spec_attrs(slice.id, "run-spec-2", 2), domain: Factory)

    second_attempt =
      RunAttemptLifecycle.create_retry_attempt!(failed, retry_run_spec,
        actor: "orchestrator",
        reason: "retry failed implementation"
      )

    assert second_attempt.attempt_no == 2
    assert second_attempt.run_spec_id == retry_run_spec.id
    assert second_attempt.status == :planned

    assert Ash.read!(Slice, domain: Factory)
           |> Enum.find(&(&1.id == slice.id))
           |> Map.fetch!(:state) ==
             :drafted

    assert Enum.map(run_attempt_events(failed.id), & &1.payload["status"]) == [
             "running",
             "failed"
           ]

    assert [%{"attempt_no" => 2}] =
             run_attempt_events(second_attempt.id)
             |> Enum.map(& &1.payload)
  end

  test "run attempt lifecycle records legal transitions and rejects illegal transitions", %{
    run_spec: run_spec,
    slice: slice
  } do
    attempt =
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 1), domain: Factory)

    assert_raise Ash.Error.Invalid, fn ->
      RunAttemptLifecycle.transition!(attempt, :record_evidence, actor: "runner")
    end

    attempt =
      attempt
      |> RunAttemptLifecycle.transition!(:start, actor: "runner")
      |> RunAttemptLifecycle.transition!(:record_evidence, actor: "runner")
      |> RunAttemptLifecycle.transition!(:review, actor: "reviewer")
      |> RunAttemptLifecycle.transition!(:gate, actor: "gate")
      |> RunAttemptLifecycle.transition!(:report, actor: "reporter")

    assert attempt.status == :reported

    assert Enum.map(run_attempt_events(attempt.id), & &1.payload["status"]) == [
             "running",
             "evidence_recorded",
             "reviewed",
             "gated",
             "reported"
           ]
  end

  test "retry creation requires a failed attempt and next-number fresh run spec", %{
    run_spec: run_spec,
    slice: slice
  } do
    attempt =
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 1), domain: Factory)

    retry_run_spec =
      Ash.create!(RunSpec, run_spec_attrs(slice.id, "run-spec-2", 2), domain: Factory)

    assert_raise ArgumentError, ~r/failed RunAttempt/, fn ->
      RunAttemptLifecycle.create_retry_attempt!(attempt, retry_run_spec)
    end

    failed =
      attempt
      |> RunAttemptLifecycle.transition!(:start, actor: "runner")
      |> RunAttemptLifecycle.transition!(:fail, actor: "runner")

    assert_raise ArgumentError, ~r/fresh/, fn ->
      RunAttemptLifecycle.create_retry_attempt!(failed, run_spec)
    end
  end

  test "agent sessions record untrusted adapter output", %{run_spec: run_spec, slice: slice} do
    attempt =
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 1), domain: Factory)

    session =
      Ash.create!(
        AgentSession,
        %{
          run_attempt_id: attempt.id,
          run_prompt_id: Ash.UUID.generate(),
          agent_profile_id: Ash.UUID.generate(),
          adapter_session_id: "pi-session-1",
          role: :implementer,
          base_commit: "abc123",
          status: :running,
          raw_result_ref: "artifacts/sessions/pi-session-1.json",
          cost_estimate: Decimal.new("0.42"),
          tokens: 1_024
        },
        domain: Factory
      )

    assert session.role == :implementer
    assert session.tokens == 1_024

    updated = Ash.update!(session, %{status: :succeeded}, domain: Factory)
    assert updated.status == :succeeded
  end

  test "station runs enforce domain idempotency keys", %{run_spec: run_spec, slice: slice} do
    attempt =
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 1), domain: Factory)

    attrs = station_run_attrs(slice.id, attempt.id, nil, "implement")

    station_run = Ash.create!(StationRun, attrs, domain: Factory)
    assert station_run.status == :queued

    updated =
      Ash.update!(
        station_run,
        %{
          status: :running,
          lease_owner: "worker-1",
          lease_expires_at: DateTime.add(DateTime.utc_now(:microsecond), 60, :second),
          heartbeat_at: DateTime.utc_now(:microsecond)
        },
        domain: Factory
      )

    assert updated.lease_owner == "worker-1"

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(StationRun, attrs, domain: Factory)
    end
  end

  test "station effects declare side effects before execution and enforce idempotency", %{
    run_spec: run_spec,
    slice: slice
  } do
    attempt =
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 1), domain: Factory)

    station_run =
      Ash.create!(StationRun, station_run_attrs(slice.id, attempt.id, nil, "gate"),
        domain: Factory
      )

    attrs = %{
      station_run_id: station_run.id,
      effect_kind: :container_start,
      idempotency_key: "effect:#{station_run.id}:container",
      cleanup_required: true,
      cleanup_status: :pending
    }

    effect = Ash.create!(StationEffect, attrs, domain: Factory)
    assert effect.status == :declared
    assert effect.cleanup_required

    updated =
      Ash.update!(effect, %{status: :unknown, observed_ref: "docker:abc"}, domain: Factory)

    assert updated.status == :unknown

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(StationEffect, attrs, domain: Factory)
    end
  end

  defp run_attempt_attrs(slice_id, run_spec_id, attempt_no) do
    %{
      slice_id: slice_id,
      run_spec_id: run_spec_id,
      attempt_no: attempt_no,
      base_commit: "abc123",
      status: :planned,
      outcome: :none,
      orchestrator_version: "conveyor@0.1.0",
      trace_id: "trace-#{attempt_no}"
    }
  end

  defp station_run_attrs(slice_id, run_attempt_id, agent_session_id, station) do
    station_spec_sha256 = digest("station:#{station}")
    attempt_no = 1

    %{
      run_attempt_id: run_attempt_id,
      agent_session_id: agent_session_id,
      slice_id: slice_id,
      station: station,
      attempt_no: attempt_no,
      station_spec_sha256: station_spec_sha256,
      idempotency_key: "#{run_attempt_id}:#{station}:#{station_spec_sha256}:#{attempt_no}",
      input_sha256: digest("input:#{station}"),
      status: :queued,
      artifact_refs: []
    }
  end

  defp run_spec_attrs(slice_id, seed, attempt_no) do
    run_spec_sha256 = digest(seed)

    %{
      slice_id: slice_id,
      attempt_no: attempt_no,
      run_spec_json_ref: "artifacts/run-specs/#{seed}.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi", "model" => "gpt-5"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: station_plan(run_spec_sha256),
      station_plan_sha256: digest("station-plan-#{seed}"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp station_plan(run_spec_sha256) do
    %{
      "schema_version" => "conveyor.station_plan@1",
      "stations" => [
        %{
          "key" => "implement",
          "input" => %{"run_spec_sha256" => run_spec_sha256},
          "output" => %{"run_spec_sha256" => run_spec_sha256}
        }
      ]
    }
  end

  defp run_attempt_events(run_attempt_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(
      &(&1.run_attempt_id == run_attempt_id and
          &1.type in ["run_attempt.transitioned", "run_attempt.retry_created"])
    )
    |> Enum.sort_by(&DateTime.to_unix(&1.occurred_at, :microsecond))
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
