defmodule Conveyor.Events.DurableCatchUp do
  @moduledoc """
  Durable segment replay plus live-message sequence filtering.
  """

  defstruct last_sequence: 0

  @type t :: %__MODULE__{last_sequence: non_neg_integer()}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{last_sequence: Keyword.get(opts, :last_sequence, 0)}
  end

  @spec replay_after(map(), non_neg_integer(), Path.t() | nil) :: [map()]
  def replay_after(manifest, last_sequence, root \\ nil) when is_map(manifest) do
    manifest
    |> Map.get("segments", [])
    |> Enum.flat_map(&segment_events(&1, root))
    |> Enum.filter(&(sequence(&1) > last_sequence))
    |> Enum.sort_by(&sequence/1)
  end

  @spec accept_live(t(), map()) :: {:ok, t(), map()} | {:ignore, t()}
  def accept_live(%__MODULE__{} = state, event) when is_map(event) do
    event_sequence = sequence(event)

    if event_sequence > state.last_sequence do
      {:ok, %{state | last_sequence: event_sequence}, event}
    else
      {:ignore, state}
    end
  end

  defp segment_events(%{"events" => events}, _root) when is_list(events), do: events
  defp segment_events(%{events: events}, _root) when is_list(events), do: events

  # Segment carrying its own root (inline shape).
  defp segment_events(%{"path" => path, "root" => root}, _root), do: read_segment(root, path)

  # Real SegmentWriter manifest segment: "path" is relative to the caller-known root
  # (SegmentWriter.write_manifest! emits path/bytes/digest/sequence_* with no "root").
  defp segment_events(%{"path" => path}, root) when is_binary(root), do: read_segment(root, path)

  defp segment_events(_segment, _root), do: []

  defp read_segment(root, path) do
    root
    |> Path.join(path)
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp sequence(%{"sequence" => sequence}), do: sequence
  defp sequence(%{sequence: sequence}), do: sequence
end
