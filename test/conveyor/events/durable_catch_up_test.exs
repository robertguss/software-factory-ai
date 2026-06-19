defmodule Conveyor.Events.DurableCatchUpTest do
  use ExUnit.Case, async: true

  alias Conveyor.Events.DurableCatchUp

  test "loads durable segment events after the last committed sequence" do
    manifest = %{
      "segments" => [
        %{
          "events" => [
            %{"sequence" => 1, "event_id" => "event-1"},
            %{"sequence" => 2, "event_id" => "event-2"}
          ]
        },
        %{
          "events" => [
            %{"sequence" => 3, "event_id" => "event-3"},
            %{"sequence" => 4, "event_id" => "event-4"}
          ]
        }
      ]
    }

    assert DurableCatchUp.replay_after(manifest, 2) == [
             %{"sequence" => 3, "event_id" => "event-3"},
             %{"sequence" => 4, "event_id" => "event-4"}
           ]
  end

  test "ignores duplicate and out-of-order live messages by sequence" do
    state = DurableCatchUp.new(last_sequence: 3)

    assert {:ignore, state} = DurableCatchUp.accept_live(state, %{"sequence" => 3})
    assert {:ignore, state} = DurableCatchUp.accept_live(state, %{"sequence" => 2})

    assert {:ok, state, %{"sequence" => 4}} =
             DurableCatchUp.accept_live(state, %{"sequence" => 4})

    assert {:ignore, ^state} = DurableCatchUp.accept_live(state, %{"sequence" => 4})

    assert {:ok, _state, %{"sequence" => 5}} =
             DurableCatchUp.accept_live(state, %{"sequence" => 5})
  end

  test "replays events from a real file-backed SegmentWriter manifest" do
    alias Conveyor.Events.SegmentWriter

    root = Path.join(System.tmp_dir!(), "conveyor-durable-#{System.unique_integer([:positive])}")

    writer = SegmentWriter.new(root)
    {writer, _} = SegmentWriter.append(writer, %{"sequence" => 1, "event_id" => "event-1"})
    {writer, _} = SegmentWriter.append(writer, %{"sequence" => 2, "event_id" => "event-2"})
    {_writer, _} = SegmentWriter.close(writer)

    manifest = Path.join(root, "manifest.json") |> File.read!() |> Jason.decode!()

    # Manifest segments are path-backed (no inline "events"); replay must read the files.
    assert DurableCatchUp.replay_after(manifest, 1, root) == [
             %{"sequence" => 2, "event_id" => "event-2"}
           ]
  end
end
