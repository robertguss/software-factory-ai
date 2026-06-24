defmodule Mix.Tasks.Conveyor.RunTest do
  @moduledoc """
  Coverage for the `mix conveyor.run` task's workspace isolation: the loop
  resets/cleans/commits its workspace, so the task must never mutate the user's
  `--workspace` directory. We stub the serial driver (via the process key
  PlanRunner already supports) to capture the workspace path it is handed, and
  the exit fun so the task does not halt the test VM.
  """
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  import Conveyor.FactoryFixtures

  @contract %{
    "schema_version" => "conveyor.plan@1",
    "project" => %{"key" => "tp", "base_ref" => "main"},
    "goal" => "Test plan goal",
    "non_goals" => [],
    "requirements" => [
      %{"key" => "REQ-001", "text" => "r", "risk" => "low", "source_ref" => "p#r"}
    ],
    "acceptance_criteria" => [
      %{
        "key" => "AC-001",
        "text" => "a",
        "requirement_refs" => ["REQ-001"],
        "required_test_refs" => []
      }
    ],
    "verification_commands" => [
      %{"key" => "pytest", "argv" => ["pytest", "-q"], "profile" => "verify"}
    ],
    "decisions" => [],
    "slices" => [
      %{
        "key" => "SLICE-001",
        "title" => "First",
        "requirement_refs" => ["REQ-001"],
        "likely_files" => [],
        "conflict_domains" => [],
        "autonomy_ceiling" => "L1"
      }
    ]
  }

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

    :ok
  end

  defp write_plan! do
    path = Path.join(temp_dir!("conveyor-run-plan"), "conveyor.plan.json")
    File.write!(path, Jason.encode!(@contract))
    path
  end

  defp workspace_with_sentinel! do
    ws = temp_dir!("conveyor-run-ws")
    File.write!(Path.join(ws, "sentinel.txt"), "original\n")
    ws
  end

  defp driver_workspace(opts),
    do: opts |> Keyword.fetch!(:run_spec_opts) |> Keyword.fetch!(:workspace_path)

  test "by default runs on an isolated copy, leaving --workspace untouched" do
    plan = write_plan!()
    ws = workspace_with_sentinel!()

    out = capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan, "--workspace", ws]) end)

    assert_received {:driver, _input, opts}
    isolated = driver_workspace(opts)

    # The driver ran somewhere OTHER than the user's dir...
    refute isolated == Path.expand(ws)
    # ...on a faithful copy (the sentinel came along)...
    assert File.read!(Path.join(isolated, "sentinel.txt")) == "original\n"
    # ...and the isolated path is reported in the JSON verdict (stdout stays pure JSON;
    # the human notice goes to stderr).
    assert out =~ ~s("workspace":"#{isolated}")
    assert_received {:exit_code, _code}
  end

  test "--in-place runs directly in --workspace" do
    plan = write_plan!()
    ws = workspace_with_sentinel!()

    capture_io(fn -> Mix.Tasks.Conveyor.Run.run([plan, "--workspace", ws, "--in-place"]) end)

    assert_received {:driver, _input, opts}
    assert driver_workspace(opts) == ws
  end
end
