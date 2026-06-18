defmodule Mix.Tasks.ConveyorReplayTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Factory
  alias Conveyor.Factory.Project
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
end
