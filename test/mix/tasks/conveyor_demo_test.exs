defmodule Mix.Tasks.ConveyorDemoTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.FactoryFixtures

  @base_commit String.duplicate("d", 40)

  test "runs the hermetic demo and prints projected artifact summary" do
    blob_root = FactoryFixtures.temp_dir!("demo-blobs")
    projection_root = FactoryFixtures.temp_dir!("demo-projection")
    test_pid = self()

    Process.put(:conveyor_seed_sample_git_fun, fn _repo_root, ["rev-parse", "HEAD"] ->
      {@base_commit <> "\n", 0}
    end)

    Process.put(:conveyor_demo_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)

    on_exit(fn ->
      Process.delete(:conveyor_seed_sample_git_fun)
      Process.delete(:conveyor_demo_exit_fun)
    end)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.demo")

        Mix.Task.run("conveyor.demo", [
          "--blob-root",
          blob_root,
          "--projection-root",
          projection_root
        ])
      end)

    assert_received {:exit_code, 0}

    summary = output |> String.trim() |> Jason.decode!()

    assert summary["status"] == "succeeded"
    assert summary["adapter"] == "fake"
    assert summary["network"] == "none"
    assert summary["credentials_required"] == false
    assert summary["station_count"] == 1
    assert summary["artifact_count"] == 1
    assert summary["run_attempt_id"]
    assert summary["projection_path"] == Path.join(projection_root, summary["run_attempt_id"])

    for path <-
          ~w(manifest.json dossier.md evidence.json review.json gate.json diff.patch pr_body.md) do
      assert File.exists?(Path.join(summary["projection_path"], path))
    end

    assert File.exists?(Path.join(summary["projection_path"], "demo/fake-runner.json"))
    assert summary["bundle_root_sha256"] =~ ~r/^[0-9a-f]{64}$/
    assert ExitCodes.fetch!(:success) == 0
  end
end
