defmodule Mix.Tasks.ConveyorReportTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.FactoryFixtures

  test "regenerates a run report idempotently and prints machine-readable paths" do
    blob_root = FactoryFixtures.temp_dir!("report-task-blobs")
    projection_root = FactoryFixtures.temp_dir!("report-task-projection")

    %{artifact_content: content, projection_path: projection_path, run_attempt: run_attempt} =
      FactoryFixtures.create_artifact_run!(
        blob_root: blob_root,
        artifact_content: "mix report artifact\n",
        projection_path: "evidence/report.txt"
      )

    first = run_report(run_attempt.id, blob_root, projection_root)
    second = run_report(run_attempt.id, blob_root, projection_root)

    projected_file = Path.join([projection_root, run_attempt.id, projection_path])
    manifest_path = Path.join([projection_root, run_attempt.id, "manifest.json"])

    assert first == second
    assert File.read!(projected_file) == content
    assert File.exists?(manifest_path)

    assert first["artifact_count"] == 1
    assert first["run_attempt_id"] == run_attempt.id
    assert first["projection_path"] == Path.join(projection_root, run_attempt.id)
    assert first["manifest_path"] == manifest_path
    assert projected_file in first["entry_paths"]

    for path <- ~w(diff.patch dossier.md evidence.json gate.json review.json) do
      assert Path.join([projection_root, run_attempt.id, path]) in first["entry_paths"]
    end

    assert File.exists?(Path.join([projection_root, run_attempt.id, "pr_body.md"]))
    assert first["manifest_sha256"] =~ ~r/^[0-9a-f]{64}$/
    assert first["bundle_root_sha256"] =~ ~r/^[0-9a-f]{64}$/
  end

  defp run_report(run_attempt_id, blob_root, projection_root) do
    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.report")

        Mix.Task.run("conveyor.report", [
          run_attempt_id,
          "--blob-root",
          blob_root,
          "--projection-root",
          projection_root
        ])
      end)

    output |> String.trim() |> Jason.decode!()
  end
end
