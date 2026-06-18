defmodule Mix.Tasks.ConveyorMarkExternallyMergedTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  import Conveyor.FactoryFixtures

  test "records an external integration commit from the CLI" do
    fixture = create_artifact_run!(blob_root: temp_dir!("mark-external-cli"))
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.mark_externally_merged")

        Mix.Task.run("conveyor.mark_externally_merged", [
          fixture.run_attempt.id,
          "--actor",
          "human@example.test",
          "--external-commit",
          String.duplicate("b", 40),
          "--rationale",
          "Merged manually."
        ])
      end)

    approval = Jason.decode!(output)

    assert approval["run_attempt_id"] == fixture.run_attempt.id
    assert approval["decision"] == "recorded_external_action"
    assert approval["external_commit"] == String.duplicate("b", 40)
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_mark_externally_merged_exit_fun)
  end

  test "records not-integrated from the CLI" do
    fixture = create_artifact_run!(blob_root: temp_dir!("not-integrated-cli"))
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.mark_externally_merged")

        Mix.Task.run("conveyor.mark_externally_merged", [
          fixture.run_attempt.id,
          "--actor",
          "human@example.test",
          "--not-integrated",
          "--rationale",
          "Not merged."
        ])
      end)

    approval = Jason.decode!(output)

    assert approval["decision"] == "not_integrated"
    assert is_nil(approval["external_commit"])
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_mark_externally_merged_exit_fun)
  end

  defp put_exit_fun do
    test_pid = self()

    Process.put(:conveyor_mark_externally_merged_exit_fun, fn code ->
      send(test_pid, {:exit_code, code})
    end)
  end
end
