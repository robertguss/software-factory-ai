defmodule Conveyor.StationTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Artifacts.BlobStore
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
  alias Conveyor.Station

  defmodule SampleStation do
    use Conveyor.Station, station: "sample"

    @impl Conveyor.Station
    def effects(_input), do: [%{effect_kind: :process_exec}]

    @impl Conveyor.Station
    def run(_input, context) do
      declared_effects =
        StationEffect
        |> Ash.read!(domain: Factory)
        |> Enum.filter(&(&1.station_run_id == context.station_run.id))

      send(
        Process.get(:station_test_pid),
        {:ran, context.station_run.id, length(declared_effects)}
      )

      {:ok,
       %{
         "summary" => "sample station complete",
         artifacts: [
           %{
             kind: "run-log",
             media_type: "text/plain",
             projection_path: "artifacts/stations/sample/log.txt",
             content: "sample station log\n"
           }
         ]
       }}
    end
  end

  setup do
    Process.put(:station_test_pid, self())

    project =
      Ash.create!(
        Project,
        %{name: "Station sample", local_path: "/tmp/station-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Station plan",
          intent: "Exercise station execution.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Station epic", description: "Station execution."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Station slice", position: 1},
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
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-station"
        },
        domain: Factory
      )

    %{blob_root: temp_dir!("station-blobs"), run_attempt: run_attempt}
  end

  test "executes station mechanics once and reuses succeeded idempotency key", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    now = ~U[2026-06-18 00:00:00.000000Z]

    result =
      SampleStation.execute!(run_attempt, %{"input" => "value"},
        actor: "worker-1",
        blob_root: blob_root,
        now: now,
        completed_at: DateTime.add(now, 5, :second)
      )

    assert_receive {:ran, station_run_id, 1}
    assert result.station_run.id == station_run_id
    assert result.station_run.status == :succeeded
    assert result.station_run.lease_owner == "worker-1"
    assert result.station_run.heartbeat_at == now
    assert result.station_run.lease_expires_at == DateTime.add(now, 60, :second)
    assert result.station_run.output_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/
    assert result.station_run.artifact_refs == ["artifacts/stations/sample/log.txt"]
    refute result.reused?

    assert [effect] = Ash.read!(StationEffect, domain: Factory)
    assert effect.station_run_id == station_run_id
    assert effect.status == :declared

    assert [artifact] = Ash.read!(Artifact, domain: Factory)
    assert artifact.station_run_id == station_run_id
    assert artifact.sha256 =~ ~r/^sha256:[0-9a-f]{64}$/
    assert artifact.blob_ref =~ ~r|^sha256/[0-9a-f]{2}/[0-9a-f]{64}$|
    assert BlobStore.read!(artifact.blob_ref, blob_root: blob_root) == "sample station log\n"

    assert [event] = station_events(station_run_id)
    assert event.type == "station.succeeded"
    assert event.payload["output_sha256"] == result.station_run.output_sha256

    retry =
      SampleStation.execute!(run_attempt, %{"input" => "value"},
        actor: "worker-1",
        blob_root: blob_root
      )

    assert retry.reused?
    assert retry.station_run.id == station_run_id
    assert retry.ledger_event.id == event.id
    refute_receive {:ran, ^station_run_id, _declared_effects}

    assert length(Ash.read!(StationRun, domain: Factory)) == 1
    assert length(Ash.read!(StationEffect, domain: Factory)) == 1
    assert length(Ash.read!(Artifact, domain: Factory)) == 1
    assert length(station_events(station_run_id)) == 1
  end

  test "idempotency key uses run attempt, station, station spec digest, and attempt number", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    input = %{"input" => "value"}
    station_spec_sha256 = SampleStation.station_spec_sha256(input)

    expected =
      Station.idempotency_key(
        run_attempt.id,
        "sample",
        station_spec_sha256,
        run_attempt.attempt_no
      )

    result = SampleStation.execute!(run_attempt, input, actor: "worker-1", blob_root: blob_root)

    assert result.station_run.idempotency_key == expected
  end

  test "heartbeat refreshes lease without creating new station rows", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    result =
      SampleStation.execute!(run_attempt, %{"input" => "heartbeat"},
        actor: "worker-1",
        blob_root: blob_root
      )

    refreshed =
      Station.heartbeat!(result.station_run,
        now: ~U[2026-06-18 00:01:00.000000Z],
        lease_seconds: 120
      )

    assert refreshed.heartbeat_at == ~U[2026-06-18 00:01:00.000000Z]
    assert refreshed.lease_expires_at == ~U[2026-06-18 00:03:00.000000Z]
    assert length(Ash.read!(StationRun, domain: Factory)) == 1
  end

  defp station_events(station_run_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.station_run_id == station_run_id and &1.type == "station.succeeded"))
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-station")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/station.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi", "model" => "gpt-5"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: station_plan(run_spec_sha256),
      station_plan_sha256: digest("station-plan"),
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
          "key" => "sample",
          "input" => %{"run_spec_sha256" => run_spec_sha256},
          "output" => %{"run_spec_sha256" => run_spec_sha256}
        }
      ]
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end
end
