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

  test "run emits a machine-readable serial driver verdict for a normalized plan" do
    test_pid = self()

    Process.put(:conveyor_run_exit_fun, fn code ->
      send(test_pid, {:exit_code, :conveyor_run_exit_fun, code})
    end)

    Process.put(:conveyor_run_serial_driver, fn input, opts ->
      send(test_pid, {:serial_driver_input, input, opts})

      %Conveyor.Planning.SerialDriver.Result{
        status: :passed,
        order: input.selected_slice_ids,
        events: [
          %{
            "slice_id" => "SLICE-001",
            "sequence" => 1,
            "status" => "passed",
            "gate_result" => "first_pass",
            "run_attempt_outcome" => :accepted,
            "findings" => []
          }
        ],
        report: %{
          "status" => "serial_execution_recorded",
          "first_pass_gate_success_rate" => 1.0,
          "replay_fidelity" => %{"status" => "baseline_absent"}
        }
      }
    end)

    on_exit(fn ->
      Process.delete(:conveyor_run_exit_fun)
      Process.delete(:conveyor_run_serial_driver)
    end)

    result =
      run_task("conveyor.run", [
        "samples/beads_insight/conveyor.plan.yml",
        "--adapter",
        "reference_solution",
        "--workspace",
        "samples/beads_insight"
      ])

    assert result["status"] == "passed"
    assert result["plan_path"] =~ "samples/beads_insight/conveyor.plan.yml"
    assert result["adapter"] == "reference_solution"
    assert result["slice_count"] == 7

    assert result["serial_order"] ==
             ~w(SLICE-001 SLICE-002 SLICE-003 SLICE-004 SLICE-005 SLICE-006 SLICE-007)

    assert result["first_pass_gate_success_rate"] == 1.0
    assert result["replay_fidelity"]["status"] == "baseline_absent"
    assert_received {:exit_code, :conveyor_run_exit_fun, 0}

    assert_received {:serial_driver_input, input, opts}

    assert input.selected_slice_ids ==
             ~w(SLICE-001 SLICE-002 SLICE-003 SLICE-004 SLICE-005 SLICE-006 SLICE-007)

    assert length(input.work_graph["slices"]) == 7
    assert Enum.all?(Map.values(opts[:slices_by_stable_key]), & &1.id)
    assert opts[:patch_refs_by_slice]["SLICE-001"] =~ "reference_slice_001_loader.patch"

    assert opts[:patch_refs_by_slice]["SLICE-007"] =~
             "reference_slice_007_envelope_assertion.patch"

    assert opts[:run_spec_opts][:agent_adapter] == Conveyor.AgentRunner.ReferenceSolution
    assert opts[:run_spec_opts][:workspace_path] =~ "samples/beads_insight"
    assert Path.type(opts[:run_spec_opts][:blob_root]) == :absolute

    refute String.starts_with?(
             opts[:run_spec_opts][:blob_root],
             opts[:run_spec_opts][:workspace_path]
           )
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
