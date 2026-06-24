defmodule Conveyor.Mix.Tasks.ConveyorRunDbTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.TaskGraph

  setup do
    test_pid = self()

    Process.put(:conveyor_run_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)

    Process.put(:conveyor_run_serial_driver, fn input, _opts ->
      send(test_pid, {:driver_called, input})
      %{status: :passed, order: input.selected_slice_ids, events: [], report: %{}}
    end)

    on_exit(fn ->
      Process.delete(:conveyor_run_exit_fun)
      Process.delete(:conveyor_run_serial_driver)
    end)

    project =
      Ash.create!(
        Project,
        %{name: "Run CLI", local_path: "/tmp/run-db-cli", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Run CLI plan",
          intent: "Run by id.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Epic", description: "Slices."},
        domain: Factory
      )

    %{plan: plan, epic: epic}
  end

  test "conveyor run <plan-id> runs an approved graph and exits success", %{
    plan: plan,
    epic: epic
  } do
    task = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
    TaskGraph.approve_task(task.id)

    out = capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan.id]) end)
    decoded = out |> String.trim() |> Jason.decode!()

    assert decoded["status"] == "passed"
    assert decoded["plan_path"] == "db:#{plan.id}"
    assert_received {:driver_called, _input}
    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "conveyor run <plan-id> refuses an unapproved graph with the approval exit code", %{
    plan: plan,
    epic: epic
  } do
    TaskGraph.create_task(%{epic_id: epic.id, title: "Unapproved"})

    capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan.id]) end)

    refute_received {:driver_called, _input}
    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:plan_or_readiness_blocked)
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
