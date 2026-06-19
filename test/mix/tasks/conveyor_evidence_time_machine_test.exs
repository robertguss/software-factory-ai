defmodule Mix.Tasks.ConveyorEvidenceTimeMachineTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "diff_artifacts prints canonical JSON comparison" do
    tmp = temp_dir!("evidence-time-machine")
    left_path = Path.join(tmp, "left.json")
    right_path = Path.join(tmp, "right.json")

    File.write!(left_path, Jason.encode!(subject("artifact:left", "sha256:left")))
    File.write!(right_path, Jason.encode!(subject("artifact:right", "sha256:right")))

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.diff_artifacts")
        Mix.Task.run("conveyor.diff_artifacts", [left_path, right_path])
      end)

    report = output |> String.trim() |> Jason.decode!()

    assert report["schema_version"] == "conveyor.evidence_time_machine.diff@1"
    assert report["command"] == "diff_artifacts"
    assert report["comparison"]["summary_status"] == "materially_different"
    assert report["comparison"]["materiality_labels"] == ["evidence_changing"]
    assert report["canonical_json"] == true
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "conveyor-test-evidence-time-machine"))
  end

  test "diff commands and why_different share the canonical comparison report" do
    tmp = temp_dir!("evidence-time-machine-many")
    left_path = Path.join(tmp, "left.json")
    right_path = Path.join(tmp, "right.json")

    File.write!(left_path, Jason.encode!(subject("left", "sha256:left")))
    File.write!(right_path, Jason.encode!(subject("right", "sha256:right")))

    for {task, expected_command, extra_args} <- [
          {"conveyor.diff_runs", "diff_runs", ["--section", "gate"]},
          {"conveyor.diff_plans", "diff_plans", []},
          {"conveyor.diff_candidates", "diff_candidates", []},
          {"conveyor.diff_grants", "diff_grants", []},
          {"conveyor.why_different", "why_different", []}
        ] do
      output =
        capture_io(fn ->
          Mix.Task.reenable(task)
          Mix.Task.run(task, [left_path, right_path | extra_args])
        end)

      report = output |> String.trim() |> Jason.decode!()

      assert report["command"] == expected_command
      assert report["comparison"]["summary_status"] == "materially_different"
    end
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "conveyor-test-evidence-time-machine-many"))
  end

  test "why_stale explains stale subject metadata" do
    tmp = temp_dir!("evidence-time-machine-stale")
    subject_path = Path.join(tmp, "subject.json")

    File.write!(
      subject_path,
      Jason.encode!(
        Map.put(subject("run:old", "sha256:old"), "stale_reasons", ["cassette_stale"])
      )
    )

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.why_stale")
        Mix.Task.run("conveyor.why_stale", [subject_path])
      end)

    report = output |> String.trim() |> Jason.decode!()

    assert report["schema_version"] == "conveyor.evidence_time_machine.why_stale@1"
    assert report["subject_id"] == "run:old"
    assert report["stale"] == true
    assert report["reasons"] == ["cassette_stale"]
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "conveyor-test-evidence-time-machine-stale"))
  end

  defp subject(id, digest) do
    %{
      "subject_kind" => "artifact",
      "subject_id" => id,
      "digest" => digest,
      "available?" => true,
      "authorized?" => true,
      "digest_verified?" => true
    }
  end

  defp temp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "conveyor-test-#{name}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
