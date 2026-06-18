defmodule Conveyor.BaselineAcceptanceTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AcceptanceCalibration
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.BaselineHealth
  alias Conveyor.Factory
  alias Conveyor.Factory.TestPackCalibration
  alias Conveyor.Factory.VerificationSuite
  alias Conveyor.SampleTasksSeed

  @base_commit String.duplicate("c", 40)

  setup do
    Process.put(:conveyor_seed_sample_git_fun, fn _repo_root, ["rev-parse", "HEAD"] ->
      {@base_commit <> "\n", 0}
    end)

    on_exit(fn -> Process.delete(:conveyor_seed_sample_git_fun) end)

    %{
      blob_root: temp_dir!("baseline-acceptance-blobs"),
      seed: SampleTasksSeed.seed!(base_commit: @base_commit)
    }
  end

  test "baseline health passes when baseline regression commands are green", %{seed: seed} do
    Ash.create!(
      VerificationSuite,
      %{
        project_id: seed.project.id,
        slice_id: seed.slice.id,
        key: "baseline-pytest",
        suite_kind: :baseline_regression,
        command_specs: [command_spec(["pytest", "-q"])],
        expected_on_base: :pass,
        expected_on_patch: :pass,
        required: true,
        result_format: :stdout
      },
      domain: Factory
    )

    result =
      BaselineHealth.run!(seed.run_spec,
        runner: fn _command -> %{exit_code: 0, stdout: "ok\n"} end
      )

    assert result.status == :passed
    assert [%{"key" => "baseline-pytest", "status" => "passed"}] = result.suites
  end

  test "acceptance calibration records expected red failures on base", %{
    blob_root: blob_root,
    seed: seed
  } do
    calibration =
      AcceptanceCalibration.run!(seed.run_spec,
        blob_root: blob_root,
        runner: fn _command -> %{exit_code: 1, stdout: "test_complete_task failed\n"} end
      )

    assert calibration.status == :valid
    assert calibration.expected_failures == seed.test_pack.required_test_refs
    assert calibration.unexpected_passes == []
    assert calibration.base_commit == seed.run_spec.base_commit

    result = BlobStore.read!(calibration.result_ref, blob_root: blob_root) |> Jason.decode!()
    assert result["schema_version"] == "conveyor.acceptance_calibration@1"
    assert [persisted] = Ash.read!(TestPackCalibration, domain: Factory)
    assert persisted.id == calibration.id
  end

  test "acceptance calibration invalidates unexpected green tests", %{
    blob_root: blob_root,
    seed: seed
  } do
    calibration =
      AcceptanceCalibration.run!(seed.run_spec,
        blob_root: blob_root,
        runner: fn _command -> %{exit_code: 0, stdout: "all passed\n"} end
      )

    assert calibration.status == :invalid
    assert calibration.expected_failures == []
    assert calibration.unexpected_passes == seed.test_pack.required_test_refs
  end

  defp command_spec(argv) do
    %{
      "key" => List.first(argv),
      "argv" => argv,
      "cwd" => "samples/tasks_service",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
      "result_format" => "stdout"
    }
  end

  defp temp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
