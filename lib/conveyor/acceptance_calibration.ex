defmodule Conveyor.AcceptanceCalibration do
  @moduledoc """
  Calibrates locked acceptance tests against the base commit.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.TestPack
  alias Conveyor.Factory.TestPackCalibration

  @spec run!(RunSpec.t(), keyword()) :: TestPackCalibration.t()
  def run!(%RunSpec{} = run_spec, opts \\ []) do
    test_pack = latest_test_pack!(run_spec.slice_id)
    command_results = Enum.map(test_pack.runner_command_specs, &run_command(&1, opts))
    all_green? = Enum.all?(command_results, &(&1["exit_code"] == 0))

    attrs =
      calibration_attrs(run_spec, test_pack, command_results, all_green?)
      |> Map.put(:result_ref, write_result!(run_spec, test_pack, command_results, opts))

    Ash.create!(TestPackCalibration, attrs, domain: Factory)
  end

  defp calibration_attrs(run_spec, test_pack, _command_results, false = _all_green?) do
    %{
      test_pack_id: test_pack.id,
      run_spec_id: run_spec.id,
      base_commit: run_spec.base_commit,
      expected_failures: test_pack.required_test_refs,
      unexpected_passes: [],
      unexpected_failures: [],
      status: :valid
    }
  end

  defp calibration_attrs(run_spec, test_pack, _command_results, true = _all_green?) do
    %{
      test_pack_id: test_pack.id,
      run_spec_id: run_spec.id,
      base_commit: run_spec.base_commit,
      expected_failures: [],
      unexpected_passes: test_pack.required_test_refs,
      unexpected_failures: [],
      status: :invalid
    }
  end

  defp write_result!(run_spec, test_pack, command_results, opts) do
    %{
      "schema_version" => "conveyor.acceptance_calibration@1",
      "run_spec_id" => run_spec.id,
      "test_pack_id" => test_pack.id,
      "base_commit" => run_spec.base_commit,
      "commands" => command_results
    }
    |> Jason.encode!(pretty: true)
    |> BlobStore.write!(blob_root: Keyword.get(opts, :blob_root, ".conveyor/blobs"))
    |> Map.fetch!(:ref)
  end

  defp run_command(command_spec, opts) do
    runner =
      Keyword.get(opts, :runner, fn _command -> %{exit_code: 1, stdout: "", stderr: ""} end)

    result = runner.(command_spec)

    %{
      "argv" => command_spec["argv"] || command_spec[:argv],
      "exit_code" => result_value(result, :exit_code),
      "stdout" => result_value(result, :stdout, ""),
      "stderr" => result_value(result, :stderr, "")
    }
  end

  defp result_value(result, key, default \\ nil)
  defp result_value(result, key, default) when is_map(result), do: Map.get(result, key, default)

  defp latest_test_pack!(slice_id) do
    TestPack
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first() ||
      raise ArgumentError, "Slice #{slice_id} has no TestPack"
  end
end
