defmodule Mix.Tasks.ConveyorGateCanaryTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  import Conveyor.FactoryFixtures

  @manifest Path.expand("../../../samples/tasks_service/.conveyor/canary/mutants.json", __DIR__)

  test "runs canary suite, writes mutants report, prints JSON, and exits six on false negatives" do
    tmp = temp_dir!("gate-canary-cli")
    fixture = create_artifact_run!(blob_root: tmp)
    put_exit_fun()
    on_exit(fn -> File.rm_rf(tmp) end)

    output =
      File.cd!(tmp, fn ->
        capture_io(fn ->
          Mix.Task.reenable("conveyor.gate_canary")
          Mix.Task.run("conveyor.gate_canary", [fixture.project.id, "--manifest", @manifest])
        end)
      end)

    report = Jason.decode!(output)
    written = tmp |> Path.join("canary/mutants.json") |> File.read!() |> Jason.decode!()

    assert report == written
    assert report["project_id"] == fixture.project.id
    assert report["schema_version"] == "conveyor.gate_canary_run@1"
    assert report["case_count"] == 9
    assert report["false_negative_count"] == 8
    assert report["ci_exit_code"] == 6
    assert_received {:exit_code, 6}
  after
    Process.delete(:conveyor_gate_canary_exit_fun)
  end

  defp put_exit_fun do
    test_pid = self()
    Process.put(:conveyor_gate_canary_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
  end
end
