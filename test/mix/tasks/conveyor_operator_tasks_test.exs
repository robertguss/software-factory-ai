defmodule Mix.Tasks.ConveyorOperatorTasksTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Demo
  alias Conveyor.FactoryFixtures

  @base_commit String.duplicate("e", 40)

  test "run_slice, ci, verify, and show emit machine-readable results" do
    blob_root = FactoryFixtures.temp_dir!("operator-blobs")
    projection_root = FactoryFixtures.temp_dir!("operator-projection")
    test_pid = self()

    Process.put(:conveyor_seed_sample_git_fun, fn _repo_root, ["rev-parse", "HEAD"] ->
      {@base_commit <> "\n", 0}
    end)

    Process.put(:conveyor_run_slice_station_modules, %{"seed" => Demo.FakeRunnerStation})

    for key <- [
          :conveyor_run_slice_exit_fun,
          :conveyor_ci_exit_fun,
          :conveyor_verify_exit_fun,
          :conveyor_show_exit_fun
        ] do
      Process.put(key, fn code -> send(test_pid, {:exit_code, key, code}) end)
    end

    on_exit(fn ->
      Process.delete(:conveyor_seed_sample_git_fun)
      Process.delete(:conveyor_run_slice_station_modules)
      Process.delete(:conveyor_run_slice_exit_fun)
      Process.delete(:conveyor_ci_exit_fun)
      Process.delete(:conveyor_verify_exit_fun)
      Process.delete(:conveyor_show_exit_fun)
    end)

    demo =
      Demo.run!(
        blob_root: blob_root,
        projection_root: projection_root,
        base_commit: @base_commit
      )

    run_slice =
      run_task("conveyor.run_slice", [
        demo.run_attempt.id,
        "--blob-root",
        blob_root,
        "--projection-root",
        projection_root
      ])

    assert run_slice["status"] == "succeeded"
    assert run_slice["run_attempt_id"] == demo.run_attempt.id
    assert run_slice["station_count"] == 1
    assert_received {:exit_code, :conveyor_run_slice_exit_fun, 0}

    ci =
      run_task("conveyor.ci", [
        "--blob-root",
        blob_root,
        "--projection-root",
        projection_root
      ])

    assert ci["mode"] == "ci"
    assert ci["status"] == "succeeded"
    assert ci["credentials_required"] == false
    assert_received {:exit_code, :conveyor_ci_exit_fun, 0}

    verify =
      run_task("conveyor.verify", [
        demo.run_attempt.id,
        "--blob-root",
        blob_root,
        "--projection-root",
        projection_root
      ])

    assert verify["status"] == "verified"
    assert verify["run_attempt_id"] == demo.run_attempt.id
    assert verify["manifest_sha256"] =~ ~r/^[0-9a-f]{64}$/
    assert_received {:exit_code, :conveyor_verify_exit_fun, 0}

    show = run_task("conveyor.show", [demo.run_attempt.slice_id])

    assert show["slice_id"] == demo.run_attempt.slice_id
    assert show["latest_run_attempt_id"] == demo.run_attempt.id
    assert show["station_runs"] == ["seed"]
    assert_received {:exit_code, :conveyor_show_exit_fun, 0}
    assert ExitCodes.fetch!(:success) == 0
  end

  defp run_task(task, args) do
    output =
      capture_io(fn ->
        Mix.Task.reenable(task)
        Mix.Task.run(task, args)
      end)

    output |> String.trim() |> Jason.decode!()
  end
end
