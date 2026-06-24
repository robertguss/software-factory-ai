defmodule Mix.Tasks.ConveyorDoctorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "failing doctor prints NextAction and exits with the documented code" do
    project_path =
      Path.join(System.tmp_dir!(), "conveyor-doctor-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(project_path)
    test_pid = self()

    Process.put(:conveyor_doctor_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.doctor")
        Mix.Task.run("conveyor.doctor", [project_path])
      end)

    Process.delete(:conveyor_doctor_exit_fun)

    assert output =~ "Conveyor doctor: failed"
    assert output =~ "NextAction:"
    assert output =~ "rerun: mix conveyor.doctor"
    assert_received {:exit_code, 7}
  end

  # Regression: the in-process tests above boot the app before the task runs, so
  # the real postgres check never executed against an unstarted runtime. As a
  # `mix` task, `conveyor.doctor` runs without the app started, and the postgres
  # check used to call `Postgrex.start_link/1` with :postgrex/:db_connection
  # down — crashing the run via a missing DBConnection.Watcher. Run the task in a
  # fresh subprocess and assert it degrades to a finding instead of crashing.
  @tag :doctor_cli
  test "running as a fresh `mix` task does not crash on the postgres check" do
    project_path =
      Path.join(System.tmp_dir!(), "conveyor-doctor-cli-#{System.unique_integer([:positive])}")

    File.mkdir_p!(project_path)

    {output, _status} =
      System.cmd("mix", ["conveyor.doctor", project_path],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}]
      )

    # The original failure mode: a linked connection-pool crash tore down the run
    # before the report could print.
    refute output =~ "DBConnection.Watcher", output
    refute output =~ "(EXIT from", output

    # Reaching the formatted report proves every check ran to completion.
    assert output =~ "Conveyor doctor:", output
  end
end
