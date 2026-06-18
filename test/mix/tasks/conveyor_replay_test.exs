defmodule Mix.Tasks.ConveyorReplayTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Factory
  alias Conveyor.Factory.Project
  alias Conveyor.FactoryFixtures
  alias Conveyor.Ledger

  test "prints the replay timeline as json lines" do
    project =
      Ash.create!(
        Project,
        %{name: "Replay task sample", local_path: "/tmp/replay-task-sample"},
        domain: Factory
      )

    event =
      Ledger.write!(%{
        project_id: project.id,
        idempotency_key: "ledger:#{project.id}:task",
        type: "replay.task",
        payload: %{"source" => "mix-task"},
        occurred_at: ~U[2026-06-18 01:00:00.000000Z]
      })

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.replay")
        Mix.Task.run("conveyor.replay", [])
      end)

    assert [line] = output |> String.trim() |> String.split("\n")
    assert %{"id" => id, "type" => "replay.task"} = Jason.decode!(line)
    assert id == event.id
  end

  test "prints r1 artifact replay summary for a run attempt id" do
    blob_root = FactoryFixtures.temp_dir!("replay-task-blobs")
    projection_root = FactoryFixtures.temp_dir!("replay-task-projection")

    %{artifact_content: content, projection_path: projection_path, run_attempt: run_attempt} =
      FactoryFixtures.create_artifact_run!(
        blob_root: blob_root,
        artifact_content: "mix replay artifact\n",
        projection_path: "logs/mix-r1.txt"
      )

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.replay")

        Mix.Task.run("conveyor.replay", [
          run_attempt.id,
          "--blob-root",
          blob_root,
          "--projection-root",
          projection_root
        ])
      end)

    projected_file = Path.join([projection_root, run_attempt.id, projection_path])
    assert File.read!(projected_file) == content

    decoded = output |> String.trim() |> Jason.decode!()
    assert decoded["artifact_count"] == 1
    assert decoded["run_attempt_id"] == run_attempt.id
    assert String.starts_with?(decoded["projection_path"], projection_root <> "/")
  end
end
