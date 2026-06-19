defmodule Conveyor.Events.RouterSegmentWriterTest do
  use ExUnit.Case, async: true

  alias Conveyor.Events.EventRouter
  alias Conveyor.Events.SegmentWriter

  test "EventRouter assigns sequence, correlation, causation, and trace fields" do
    events =
      EventRouter.route(
        [
          %{"event_id" => "event-1", "event_type" => "station.started"},
          %{"event_id" => "event-2", "event_type" => "station.succeeded"}
        ],
        correlation_id: "correlation-1",
        trace_id: "trace-1"
      )

    assert Enum.map(events, & &1["sequence"]) == [1, 2]
    assert Enum.map(events, & &1["correlation_id"]) == ["correlation-1", "correlation-1"]
    assert Enum.map(events, & &1["trace_context"]["trace_id"]) == ["trace-1", "trace-1"]
    assert Enum.at(events, 0)["causation_id"] == nil
    assert Enum.at(events, 1)["causation_id"] == "event-1"
  end

  test "SegmentWriter flushes immutable JSONL segments and commits a manifest" do
    root = temp_dir!("segment-writer")

    writer =
      SegmentWriter.new(root,
        max_bytes: 120,
        max_age_ms: 1_000,
        manifest_name: "manifest.json"
      )

    {writer, []} =
      SegmentWriter.append(writer, %{"sequence" => 1, "payload" => String.duplicate("a", 20)})

    {writer, [_first_segment]} =
      SegmentWriter.append(writer, %{"sequence" => 2, "payload" => String.duplicate("b", 80)})

    {_writer, flushed} = SegmentWriter.close(writer)

    assert [_second_segment] = flushed

    manifest = root |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()

    assert manifest["schema_version"] == "conveyor.event_segment_manifest@1"
    assert Enum.map(manifest["segments"], & &1["sequence_start"]) == [1, 2]
    assert Enum.map(manifest["segments"], & &1["sequence_end"]) == [1, 2]

    for segment <- manifest["segments"] do
      path = Path.join(root, segment["path"])
      assert File.regular?(path)
      assert segment["digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
      assert File.read!(path) =~ "\"sequence\""
    end
  end

  defp temp_dir!(label) do
    path = Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
