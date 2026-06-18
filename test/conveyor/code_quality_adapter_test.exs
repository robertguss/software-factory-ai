defmodule Conveyor.CodeQualityAdapterTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.CodeQualityAdapter
  alias Conveyor.CodeQualityAdapter.LocalPython
  alias Conveyor.CodeQualityAdapter.Noop
  alias Conveyor.CodeQualityAdapter.Result
  alias Conveyor.Factory
  alias Conveyor.Factory.CodeQualityRun
  alias Conveyor.SampleTasksSeed

  @base_commit String.duplicate("b", 40)

  setup do
    Process.put(:conveyor_seed_sample_git_fun, fn _repo_root, ["rev-parse", "HEAD"] ->
      {@base_commit <> "\n", 0}
    end)

    on_exit(fn -> Process.delete(:conveyor_seed_sample_git_fun) end)

    %{
      blob_root: temp_dir!("quality-blobs"),
      seed: SampleTasksSeed.seed!(base_commit: @base_commit)
    }
  end

  test "noop adapter produces a valid advisory quality result", %{
    blob_root: blob_root,
    seed: seed
  } do
    run = CodeQualityAdapter.run!(seed.project, Noop, blob_root: blob_root)
    result = quality_result!(blob_root, run.result_ref)

    assert run.adapter == "CodeQualityAdapter.Noop"
    assert run.status == :succeeded
    assert run.findings_summary == Result.empty_summary()
    assert run.new_high_risk_findings == 0

    assert result["schema_version"] == "conveyor.quality_result@1"
    assert result["adapter"] == run.adapter
    assert result["metadata"]["adapter_contract"]["advisory_only"] == true
    assert result["metadata"]["adapter_contract"]["result_schema"] == result["schema_version"]
    assert "pytest -q" in result["suggested_validation"]

    assert [%CodeQualityRun{id: id}] = Ash.read!(CodeQualityRun, domain: Factory)
    assert id == run.id
  end

  test "local python adapter cites source tests config and writes schema output", %{
    blob_root: blob_root,
    seed: seed
  } do
    run =
      CodeQualityAdapter.run!(seed.project, LocalPython,
        blob_root: blob_root,
        baseline_ref: "artifacts/quality/baseline.json"
      )

    result = quality_result!(blob_root, run.result_ref)

    assert run.adapter == "CodeQualityAdapter.LocalPython"
    assert run.baseline_ref == "artifacts/quality/baseline.json"
    assert run.status == :succeeded
    assert run.new_high_risk_findings == 0
    assert result["schema_version"] == "conveyor.quality_result@1"

    assert "tasks_service/main.py" in result["metadata"]["python_files"]
    assert "tests/test_tasks_api.py" in result["metadata"]["test_files"]
    assert "pyproject.toml" in result["metadata"]["config_files"]
    assert "pytest -q" in result["suggested_validation"]
    assert Enum.any?(result["risks"], &String.contains?(&1, "advisory context"))
  end

  test "result schema rejects invalid status" do
    assert_raise ArgumentError, ~r/status must be one of/, fn ->
      Result.new!(adapter: "bad", profile: "standard", status: :pending)
    end
  end

  defp quality_result!(blob_root, result_ref) do
    result_ref
    |> BlobStore.read!(blob_root: blob_root)
    |> Jason.decode!()
  end

  defp temp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
