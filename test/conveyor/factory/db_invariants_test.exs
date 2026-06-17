defmodule Conveyor.Factory.DbInvariantsTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationEffect
  alias Conveyor.Factory.StationRun

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Invariant sample", local_path: "/tmp/invariant-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Invariant plan",
          intent: "Check DB-backed invariants.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Invariant epic", description: "Invariants."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Invariant slice", position: 1},
        domain: Factory
      )

    run_spec =
      Ash.create!(RunSpec, run_spec_attrs(slice.id, "run-spec-invariant"), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        run_attempt_attrs(slice.id, run_spec.id, 1),
        domain: Factory
      )

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          station: "invariant",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "#{run_attempt.id}:invariant:#{digest("station")}:1",
          input_sha256: digest("input")
        },
        domain: Factory
      )

    %{
      project: project,
      run_attempt: run_attempt,
      run_spec: run_spec,
      slice: slice,
      station_run: station_run
    }
  end

  test "one active run attempt per slice is enforced at the DB layer", %{
    run_attempt: run_attempt,
    run_spec: run_spec,
    slice: slice
  } do
    assert_raise Ash.Error.Unknown, fn ->
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 2), domain: Factory)
    end

    failed =
      Ash.update!(
        run_attempt,
        %{status: :failed, outcome: :needs_rework, failure_category: "test_failure"},
        domain: Factory
      )

    assert failed.status == :failed

    next_attempt =
      Ash.create!(RunAttempt, run_attempt_attrs(slice.id, run_spec.id, 2), domain: Factory)

    assert next_attempt.attempt_no == 2
  end

  test "immutable run attempt and artifact fields cannot be updated", %{
    run_attempt: run_attempt,
    station_run: station_run
  } do
    assert_raise Ash.Error.Unknown, fn ->
      Ash.update!(run_attempt, %{base_commit: "changed-base"}, domain: Factory)
    end

    mutable =
      Ash.update!(
        run_attempt,
        %{status: :failed, outcome: :needs_rework, failure_category: "test_failure"},
        domain: Factory
      )

    assert mutable.status == :failed

    artifact =
      Ash.create!(
        Artifact,
        %{
          run_attempt_id: run_attempt.id,
          station_run_id: station_run.id,
          kind: "log",
          media_type: "text/plain",
          projection_path: "artifacts/log.txt",
          blob_ref: "cas/#{digest("artifact")}",
          sha256: digest("artifact"),
          size_bytes: 128,
          subject_kind: "run_attempt",
          producer: "gate",
          schema_version: "conveyor.artifact@1",
          sensitivity: :internal
        },
        domain: Factory
      )

    assert_raise Ash.Error.Unknown, fn ->
      Ash.update!(artifact, %{blob_ref: "cas/#{digest("changed-artifact")}"}, domain: Factory)
    end
  end

  test "station effects and ledger events enforce idempotency", %{
    project: project,
    run_attempt: run_attempt,
    slice: slice,
    station_run: station_run
  } do
    effect_attrs = %{
      station_run_id: station_run.id,
      effect_kind: :process_exec,
      idempotency_key: "effect:#{station_run.id}:exec",
      cleanup_required: true,
      cleanup_status: :pending
    }

    Ash.create!(StationEffect, effect_attrs, domain: Factory)

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(StationEffect, effect_attrs, domain: Factory)
    end

    event_attrs = %{
      project_id: project.id,
      slice_id: slice.id,
      run_attempt_id: run_attempt.id,
      station_run_id: station_run.id,
      idempotency_key: "ledger:#{run_attempt.id}:invariant",
      type: "station.completed",
      payload: %{"station_run_id" => station_run.id},
      occurred_at: DateTime.utc_now(:microsecond)
    }

    event = Ash.create!(LedgerEvent, event_attrs, domain: Factory)

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(LedgerEvent, event_attrs, domain: Factory)
    end

    assert_raise Ash.Error.Unknown, fn ->
      Ash.update!(event, %{payload: %{"changed" => true}}, domain: Factory)
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
      trace_id: "trace-invariant-#{attempt_no}"
    }
  end

  defp run_spec_attrs(slice_id, seed) do
    run_spec_sha256 = digest(seed)

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/#{seed}.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "invariant",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
