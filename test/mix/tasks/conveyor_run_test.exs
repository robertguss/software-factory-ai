defmodule Mix.Tasks.Conveyor.RunTest do
  @moduledoc """
  Coverage for the `mix conveyor.run PLAN_ID` task's workspace isolation: the loop
  resets/cleans/commits its workspace, so the task must never mutate the user's `--workspace`
  directory. We stub the serial driver (via the process key PlanRunner supports) to capture the
  workspace path it is handed, and the exit fun so the task does not halt the test VM.
  """
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  import Conveyor.FactoryFixtures

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, Plan, Project}
  alias Conveyor.TaskGraph

  setup do
    test_pid = self()

    Process.put(:conveyor_run_serial_driver, fn input, opts ->
      send(test_pid, {:driver, input, opts})
      %{status: :passed, order: input.selected_slice_ids, events: [], report: %{}}
    end)

    Process.put(:conveyor_run_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)

    on_exit(fn ->
      Process.delete(:conveyor_run_serial_driver)
      Process.delete(:conveyor_run_exit_fun)
    end)

    %{plan_id: approved_plan!()}
  end

  # An approved single-task plan so run_plan! passes the gate and reaches the (stubbed) driver.
  defp approved_plan! do
    project =
      Ash.create!(
        Project,
        %{
          name: "rt",
          local_path: "/tmp/conveyor-run-test-#{System.unique_integer([:positive])}",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Run test plan",
          intent: "Workspace isolation.",
          source_document: "db",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: "sha256:rt"
        },
        domain: Factory
      )

    epic = Ash.create!(Epic, %{plan_id: plan.id, title: "E", description: "d"}, domain: Factory)
    task = TaskGraph.create_task(%{epic_id: epic.id, title: "First"})
    TaskGraph.approve_task(task.id)
    plan.id
  end

  defp workspace_with_sentinel! do
    ws = temp_dir!("conveyor-run-ws")
    File.write!(Path.join(ws, "sentinel.txt"), "original\n")
    ws
  end

  defp driver_workspace(opts),
    do: opts |> Keyword.fetch!(:run_spec_opts) |> Keyword.fetch!(:workspace_path)

  test "by default runs on an isolated copy, leaving --workspace untouched", %{plan_id: plan_id} do
    ws = workspace_with_sentinel!()

    out = capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan_id, "--workspace", ws]) end)

    assert_received {:driver, _input, opts}
    isolated = driver_workspace(opts)

    refute isolated == Path.expand(ws)
    assert File.read!(Path.join(isolated, "sentinel.txt")) == "original\n"
    assert out =~ ~s("workspace":"#{isolated}")
    assert_received {:exit_code, _code}
  end

  test "--in-place runs directly in --workspace", %{plan_id: plan_id} do
    ws = workspace_with_sentinel!()

    capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan_id, "--workspace", ws, "--in-place"]) end)

    assert_received {:driver, _input, opts}
    assert driver_workspace(opts) == ws
  end

  test "a parked-only partial run exits parked_for_review (needs a human), not gate-failed", %{
    plan_id: plan_id
  } do
    stub_serial_driver!([
      %{"status" => "passed", "run_attempt_outcome" => :accepted},
      %{"status" => "parked", "run_attempt_outcome" => :parked}
    ])

    out = capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan_id]) end)

    assert Jason.decode!(out)["disposition"] == "parked_for_review"
    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:parked_for_review)
    refute code == ExitCodes.fetch!(:deterministic_gate_failed)
  end

  test "a hard gate failure still exits deterministic_gate_failed (no regression)", %{
    plan_id: plan_id
  } do
    stub_serial_driver!([%{"status" => "parked", "run_attempt_outcome" => :rejected}])

    out = capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan_id]) end)

    assert Jason.decode!(out)["disposition"] == "gate_failed"
    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:deterministic_gate_failed)
  end

  test "a non-UUID selector is rejected (YAML retired)" do
    assert_raise Mix.Error, fn -> Mix.Tasks.Conveyor.Run.run(["some-plan.yml"]) end
  end

  defp stub_serial_driver!(events) do
    Process.put(:conveyor_run_serial_driver, fn _input, _opts ->
      %{status: :partial, order: [], events: events, report: %{}}
    end)
  end
end
