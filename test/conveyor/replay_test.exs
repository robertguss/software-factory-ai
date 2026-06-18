defmodule Conveyor.ReplayTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Project
  alias Conveyor.FactoryFixtures
  alias Conveyor.Ledger
  alias Conveyor.Replay

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Replay sample",
          local_path: "/tmp/replay-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    %{project: project}
  end

  test "timeline is deterministically ordered by occurred_at then id", %{project: project} do
    timestamp = ~U[2026-06-18 01:00:00.000000Z]
    later = DateTime.add(timestamp, 1, :microsecond)

    first = write_event!(project, "b", later)
    second = write_event!(project, "a", timestamp)
    third = write_event!(project, "c", timestamp)

    expected =
      [second, third, first]
      |> Enum.sort_by(&{DateTime.to_unix(&1.occurred_at, :microsecond), &1.id})
      |> Enum.map(& &1.id)

    assert Replay.timeline!() |> Enum.map(& &1["id"]) == expected
    assert Replay.timeline!() == Replay.timeline!()
  end

  test "formats timeline as deterministic json lines", %{project: project} do
    event = write_event!(project, "format", ~U[2026-06-18 01:00:00.000000Z])

    output = Replay.timeline!() |> Replay.format_timeline()

    assert [line] = String.split(output, "\n")
    assert %{"id" => id, "type" => "replay.format"} = Jason.decode!(line)
    assert id == event.id
  end

  test "r1 replay regenerates artifacts for a run attempt" do
    blob_root = FactoryFixtures.temp_dir!("replay-blobs")
    projection_root = FactoryFixtures.temp_dir!("replay-projection")

    %{artifact_content: content, projection_path: projection_path, run_attempt: run_attempt} =
      FactoryFixtures.create_artifact_run!(
        blob_root: blob_root,
        artifact_content: "r1 replay artifact\n",
        projection_path: "logs/r1.txt"
      )

    result =
      Replay.project_run!(run_attempt.id,
        blob_root: blob_root,
        projection_root: projection_root
      )

    projected_file = Path.join([projection_root, run_attempt.id, projection_path])
    assert File.read!(projected_file) == content
    assert result.run_attempt_id == run_attempt.id
    assert result.artifact_count == 1
  end

  defp write_event!(project, label, occurred_at) do
    Ledger.write!(%{
      project_id: project.id,
      idempotency_key: "ledger:#{project.id}:#{label}",
      type: "replay.#{label}",
      payload: %{"label" => label},
      occurred_at: occurred_at
    })
  end
end
