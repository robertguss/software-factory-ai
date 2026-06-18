defmodule Conveyor.EffectsReconcilerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Effects.Reconciler
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationEffect
  alias Conveyor.Factory.StationRun
  alias Conveyor.Jobs.ReconcileStaleEffects

  defmodule RetryStation do
    use Conveyor.Station, station: "retry"

    @impl Conveyor.Station
    def effects(_input),
      do: [%{effect_kind: :process_exec, cleanup_required: true, cleanup_status: :pending}]

    @impl Conveyor.Station
    def run(_input, _context), do: {:ok, %{"status" => "retried"}}
  end

  test "reconciles unknown effects on stale running station runs" do
    %{station_run: station_run} = create_running_station!()

    effect =
      Ash.create!(
        StationEffect,
        %{
          station_run_id: station_run.id,
          effect_kind: :container_start,
          idempotency_key: "effect:stale-container",
          status: :unknown,
          cleanup_required: true,
          cleanup_status: :pending
        },
        domain: Factory
      )

    result =
      Reconciler.reconcile!(
        now: ~U[2026-06-18 02:00:00.000000Z],
        inspector: fn reconciled_effect ->
          assert reconciled_effect.id == effect.id
          {:ok, :missing, "container:gone"}
        end
      )

    assert result.reconciled_effects == 1
    assert result.failed_effects == 0

    reconciled = get_by_id!(StationEffect, effect.id)
    assert reconciled.status == :reconciled
    assert reconciled.cleanup_status == :completed
    assert reconciled.observed_ref == "container:gone"

    failed_station = get_by_id!(StationRun, station_run.id)
    assert failed_station.status == :failed
    assert failed_station.error_category == "effect_reconciled"
  end

  test "succeeded effects remain pending for cleanup so teardown is still owed" do
    %{station_run: station_run} = create_running_station!()

    effect =
      Ash.create!(
        StationEffect,
        %{
          station_run_id: station_run.id,
          effect_kind: :container_start,
          idempotency_key: "effect:succeeded-container",
          status: :unknown,
          cleanup_required: true,
          cleanup_status: :pending
        },
        domain: Factory
      )

    result =
      Reconciler.reconcile!(
        now: ~U[2026-06-18 02:00:00.000000Z],
        inspector: fn _effect -> {:ok, :succeeded, "container:running"} end
      )

    assert result.reconciled_effects == 1

    reconciled = get_by_id!(StationEffect, effect.id)
    assert reconciled.status == :reconciled
    # The resource still exists, so cleanup is still owed (not :completed).
    assert reconciled.cleanup_status == :pending
    assert reconciled.observed_ref == "container:running"
  end

  test "station retry is blocked while prior effects are unknown and succeeds after reconciliation" do
    %{run_attempt: run_attempt} = create_run_attempt!()

    input = %{"run_spec_sha256" => "sha256:" <> String.duplicate("1", 64)}
    station_spec_sha256 = RetryStation.station_spec_sha256(input)

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: run_attempt.slice_id,
          station: "retry",
          attempt_no: 1,
          station_spec_sha256: station_spec_sha256,
          idempotency_key:
            Conveyor.Station.idempotency_key(run_attempt.id, "retry", station_spec_sha256, 1),
          input_sha256: RetryStation.input_sha256(input),
          status: :running,
          lease_owner: "crashed-worker",
          lease_expires_at: ~U[2026-06-18 01:00:00.000000Z],
          heartbeat_at: ~U[2026-06-18 00:59:00.000000Z]
        },
        domain: Factory
      )

    effect =
      Ash.create!(
        StationEffect,
        %{
          station_run_id: station_run.id,
          effect_kind: :process_exec,
          idempotency_key: "effect:retry:process",
          status: :unknown,
          cleanup_required: true,
          cleanup_status: :pending
        },
        domain: Factory
      )

    assert_raise ArgumentError, ~r/unknown StationEffect/, fn ->
      RetryStation.execute!(run_attempt, input, blob_root: temp_dir!("blocked-retry"))
    end

    Reconciler.reconcile!(
      now: ~U[2026-06-18 02:00:00.000000Z],
      inspector: fn reconciled_effect ->
        assert reconciled_effect.id == effect.id
        {:ok, :missing, "process:gone"}
      end
    )

    result = RetryStation.execute!(run_attempt, input, blob_root: temp_dir!("allowed-retry"))

    assert result.station_run.status == :succeeded
    assert result.output == %{"status" => "retried"}
  end

  test "periodic worker reconciles stale effects with the default inspector" do
    %{station_run: station_run} = create_running_station!()

    effect =
      Ash.create!(
        StationEffect,
        %{
          station_run_id: station_run.id,
          effect_kind: :process_exec,
          idempotency_key: "effect:worker:process",
          status: :running,
          cleanup_required: true,
          cleanup_status: :pending
        },
        domain: Factory
      )

    assert :ok =
             ReconcileStaleEffects.perform(%Oban.Job{
               args: %{"now" => "2026-06-18T02:00:00.000000Z"}
             })

    reconciled = get_by_id!(StationEffect, effect.id)
    assert reconciled.status == :reconciled
    assert reconciled.cleanup_status == :completed

    failed_station = get_by_id!(StationRun, station_run.id)
    assert failed_station.status == :failed
    assert failed_station.error_category == "effect_reconciled"
  end

  defp create_running_station! do
    %{run_attempt: run_attempt} = create_run_attempt!()

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: run_attempt.slice_id,
          station: "stale",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "station:stale",
          input_sha256: digest("input"),
          status: :running,
          lease_owner: "worker",
          lease_expires_at: ~U[2026-06-18 01:00:00.000000Z],
          heartbeat_at: ~U[2026-06-18 00:59:00.000000Z]
        },
        domain: Factory
      )

    %{run_attempt: run_attempt, station_run: station_run}
  end

  defp create_run_attempt! do
    project =
      Ash.create!(
        Project,
        %{name: "Effects sample", local_path: "/tmp/effects-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Effects plan",
          intent: "Reconcile station effects.",
          source_document: "docs/effects.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Effects epic", description: "Effects."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Effects slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: "abc123",
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-effects"
        },
        domain: Factory
      )

    %{run_attempt: run_attempt}
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-effects")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/effects.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "fake"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "retry",
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

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)

  defp temp_dir!(label) do
    path = Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
