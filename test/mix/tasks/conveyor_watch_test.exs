defmodule Mix.Tasks.Conveyor.WatchTest do
  @moduledoc "uevc.3: golden replay render + --json + --follow (injected clock). e2e is uevc.4."
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.FactoryFixtures

  defp run(args), do: capture_io(fn -> Mix.Tasks.Conveyor.Watch.run(args) end)

  defp event!(project_id, type, occurred_at, attrs) do
    Ash.create!(
      LedgerEvent,
      Map.merge(
        %{
          project_id: project_id,
          type: type,
          idempotency_key: "#{type}:#{occurred_at}",
          occurred_at: occurred_at,
          payload: %{}
        },
        attrs
      ),
      domain: Factory
    )
  end

  setup do
    test_pid = self()
    Process.put(:conveyor_watch_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_watch_exit_fun) end)

    %{project: project, slices: [slice], run_attempts: run_attempts} =
      FactoryFixtures.create_run_with_ledger!(terminal: :none, slices: [%{status: "passed"}])

    [attempt] = Map.fetch!(run_attempts, slice.id)
    run_id = "RUN-WATCH-#{binary_part(project.id, 0, 8)}"

    event!(project.id, "run.started", ~U[2026-01-01 00:00:01.000000Z], %{
      payload: %{"run_id" => run_id, "slice_ids" => [slice.stable_key]}
    })

    event!(project.id, "run.slice_outcome", ~U[2026-01-01 00:00:02.000000Z], %{
      slice_id: slice.id,
      payload: %{"run_id" => run_id, "status" => "parked", "gate_result" => "scope_denied"}
    })

    %{run_id: run_id, project: project, slice: slice, attempt: attempt}
  end

  test "replays the run's event stream oldest-first with a per-event summary", %{run_id: run_id} do
    out = run([run_id])

    assert out =~ "run.started"
    assert out =~ "run.slice_outcome"
    assert out =~ "status=parked"
    assert out =~ "gate_result=scope_denied"
    # started is rendered before the outcome (chronological)
    assert :binary.match(out, "run.started") < :binary.match(out, "run.slice_outcome")

    assert_received {:exit_code, 0}
  end

  test "--json emits the conveyor.watch@1 envelope", %{run_id: run_id} do
    decoded = run([run_id, "--json"]) |> Jason.decode!()

    assert decoded["schema_version"] == "conveyor.watch@1"
    assert decoded["run_id"] == run_id
    assert decoded["event_count"] == 2
    assert Enum.map(decoded["events"], & &1["type"]) == ["run.started", "run.slice_outcome"]
    assert List.last(decoded["events"])["payload"]["status"] == "parked"
  end

  test "--follow prints events appended between polls, then stops", %{
    run_id: run_id,
    project: project
  } do
    # the injected clock appends a newer event on the first (and only) poll tick
    Process.put(:conveyor_watch_sleep_fun, fn _ms ->
      event!(project.id, "run.finished", ~U[2026-01-01 00:00:05.000000Z], %{
        payload: %{"run_id" => run_id, "status" => "complete"}
      })

      :ok
    end)

    Process.put(:conveyor_watch_follow_continues?, fn -> false end)
    on_exit(fn -> Process.delete(:conveyor_watch_sleep_fun) end)
    on_exit(fn -> Process.delete(:conveyor_watch_follow_continues?) end)

    out = run([run_id, "--follow"])

    # the event that did not exist at first render is surfaced by the follow poll
    assert out =~ "run.finished"
    assert_received {:exit_code, 0}
  end

  test "a missing run id raises usage" do
    assert_raise Mix.Error, ~r/usage: mix conveyor\.watch/, fn ->
      Mix.Tasks.Conveyor.Watch.run([])
    end
  end
end
