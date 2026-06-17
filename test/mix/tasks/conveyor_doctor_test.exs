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
end
