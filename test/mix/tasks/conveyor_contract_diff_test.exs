defmodule Mix.Tasks.ConveyorContractDiffTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  import Conveyor.FactoryFixtures

  test "prints classified contract diff JSON" do
    tmp = temp_dir!("contract-diff-cli")
    old_path = Path.join(tmp, "old.json")
    new_path = Path.join(tmp, "new.json")
    put_exit_fun()
    on_exit(fn -> File.rm_rf(tmp) end)

    File.write!(
      old_path,
      Jason.encode!(%{
        "acceptance_criteria" => ["persist", "list"],
        "policy" => %{"protected_path_globs" => ["plan.md", "tests/**"]},
        "test_pack_sha256" => "sha256:old"
      })
    )

    File.write!(
      new_path,
      Jason.encode!(%{
        "acceptance_criteria" => ["persist"],
        "policy" => %{"protected_path_globs" => ["plan.md"]},
        "test_pack_sha256" => "sha256:new"
      })
    )

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.contract_diff")
        Mix.Task.run("conveyor.contract_diff", ["--old", old_path, "--new", new_path])
      end)

    report = Jason.decode!(output)

    assert report["classifications"] == [
             "acceptance_weakened",
             "policy_weakened",
             "test_pack_changed"
           ]

    assert report["automatic_rerun_allowed"] == false
    assert report["requires_human_decision"] == true
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_contract_diff_exit_fun)
  end

  defp put_exit_fun do
    test_pid = self()

    Process.put(:conveyor_contract_diff_exit_fun, fn code ->
      send(test_pid, {:exit_code, code})
    end)
  end
end
