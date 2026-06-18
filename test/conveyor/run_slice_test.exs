defmodule Conveyor.RunSliceTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.EventOutbox
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun
  alias Conveyor.Jobs
  alias Conveyor.RunSlice

  defmodule FirstStation do
    use Conveyor.Station, station: "first"

    @impl Conveyor.Station
    def run(input, context) do
      send(Process.get(:run_slice_test_pid), {:station, :first, input, context.station_run.id})
      {:ok, %{"first_output" => "ready"}}
    end
  end

  defmodule SecondStation do
    use Conveyor.Station, station: "second"

    @impl Conveyor.Station
    def run(input, context) do
      send(Process.get(:run_slice_test_pid), {:station, :second, input, context.station_run.id})
      {:ok, %{"second_output" => Map.fetch!(input, "first_output")}}
    end
  end

  setup do
    Process.put(:run_slice_test_pid, self())
    %{run_attempt: run_attempt} = create_run_attempt!()
    %{blob_root: temp_dir!("run-slice-blobs"), run_attempt: run_attempt}
  end

  test "runs station_plan stations in order, threads outputs, and records station publication", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    now = ~U[2026-06-18 01:00:00.000000Z]

    result =
      RunSlice.run!(run_attempt,
        station_modules: station_modules(),
        actor: "orchestrator",
        blob_root: blob_root,
        now: now
      )

    assert result.status == :succeeded
    assert result.output == %{"first_output" => "ready", "second_output" => "ready"}
    assert Enum.map(result.station_runs, & &1.station) == ["first", "second"]
    assert Enum.all?(result.station_runs, &(&1.status == :succeeded))
    assert Enum.all?(result.station_runs, &(&1.lease_owner == "orchestrator"))
    assert Enum.all?(result.station_runs, &(&1.heartbeat_at == now))

    assert_receive {:station, :first, %{"seed" => "start"}, first_run_id}

    assert_receive {:station, :second,
                    %{"first_output" => "ready", "second_input" => "needs-first"}, second_run_id}

    assert first_run_id != second_run_id

    assert station_event_types() == ["station.succeeded", "station.succeeded"]
    assert length(Ash.read!(EventOutbox, domain: Factory)) == 3

    running_attempt = get_by_id!(RunAttempt, run_attempt.id)
    assert running_attempt.status == :running
  end

  test "re-running an already completed station plan reuses StationRun rows and ledger events", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    first =
      RunSlice.run!(run_attempt,
        station_modules: station_modules(),
        actor: "orchestrator",
        blob_root: blob_root
      )

    assert_receive {:station, :first, _input, _station_run_id}
    assert_receive {:station, :second, _input, _station_run_id}

    second =
      RunSlice.run!(get_by_id!(RunAttempt, run_attempt.id),
        station_modules: station_modules(),
        actor: "orchestrator",
        blob_root: blob_root
      )

    assert second.status == :succeeded
    assert Enum.map(second.station_runs, & &1.id) == Enum.map(first.station_runs, & &1.id)
    assert length(Ash.read!(StationRun, domain: Factory)) == 2
    assert length(Ash.read!(LedgerEvent, domain: Factory)) == 3
    assert length(Ash.read!(EventOutbox, domain: Factory)) == 3
    refute_receive {:station, _station, _input, _station_run_id}
  end

  test "RunSlice Oban job delegates to the orchestrator", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    Process.put(:conveyor_run_slice_station_modules, station_modules())

    on_exit(fn ->
      Process.delete(:conveyor_run_slice_station_modules)
    end)

    assert :ok =
             Jobs.RunSlice.perform(%Oban.Job{
               args: %{"run_attempt_id" => run_attempt.id, "blob_root" => blob_root}
             })

    assert_receive {:station, :first, _input, _station_run_id}
    assert_receive {:station, :second, _input, _station_run_id}

    assert Enum.map(Ash.read!(StationRun, domain: Factory), & &1.station) |> Enum.sort() == [
             "first",
             "second"
           ]
  end

  defp station_modules do
    %{"first" => FirstStation, "second" => SecondStation}
  end

  defp create_run_attempt! do
    project =
      Ash.create!(
        Project,
        %{name: "RunSlice sample", local_path: "/tmp/run-slice-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "RunSlice plan",
          intent: "Exercise happy-path station orchestration.",
          source_document: "docs/run-slice.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "RunSlice epic", description: "Station threading."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "RunSlice slice", position: 1},
        domain: Factory
      )

    run_spec_sha256 = digest("run-spec-run-slice")
    station_plan = station_plan(run_spec_sha256)

    run_spec =
      Ash.create!(
        RunSpec,
        %{
          slice_id: slice.id,
          attempt_no: 1,
          run_spec_json_ref: "artifacts/run-specs/run-slice.json",
          run_spec_sha256: run_spec_sha256,
          base_commit: "abc123",
          contract_lock_sha256: digest("contract-lock"),
          prompt_template_version: "implementation-prompt@1",
          agent_profile_snapshot: %{"adapter" => "fake"},
          policy_sha256: digest("policy"),
          diff_policy_sha256: digest("diff-policy"),
          test_pack_sha256: digest("test-pack"),
          station_plan: station_plan,
          station_plan_sha256: digest("station-plan"),
          container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
          container_image_digest: digest("image"),
          sandbox_profile: "verify",
          budget_sha256: digest("budget"),
          code_quality_profile: "standard",
          canary_suite_version: "canary@1"
        },
        domain: Factory
      )

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
          trace_id: "trace-run-slice"
        },
        domain: Factory
      )

    %{run_attempt: run_attempt, run_spec: run_spec}
  end

  defp station_plan(run_spec_sha256) do
    %{
      "schema_version" => "conveyor.station_plan@1",
      "stations" => [
        %{
          "key" => "first",
          "input" => %{"run_spec_sha256" => run_spec_sha256, "seed" => "start"},
          "output" => %{"run_spec_sha256" => run_spec_sha256, "first_output" => "ready"}
        },
        %{
          "key" => "second",
          "input" => %{"run_spec_sha256" => run_spec_sha256, "second_input" => "needs-first"},
          "output" => %{"run_spec_sha256" => run_spec_sha256, "second_output" => "ready"}
        }
      ]
    }
  end

  defp station_event_types do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.type == "station.succeeded"))
    |> Enum.sort_by(&DateTime.to_unix(&1.occurred_at, :microsecond))
    |> Enum.map(& &1.type)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
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
