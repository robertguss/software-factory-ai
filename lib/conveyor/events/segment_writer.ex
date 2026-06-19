defmodule Conveyor.Events.SegmentWriter do
  @moduledoc """
  Bounded immutable JSONL event segment writer.
  """

  defstruct root: nil,
            max_bytes: 1_048_576,
            max_age_ms: 30_000,
            manifest_name: "manifest.json",
            current_lines: [],
            current_bytes: 0,
            current_started_at_ms: nil,
            next_segment: 1,
            segments: []

  @type t :: %__MODULE__{}

  @spec new(Path.t(), keyword()) :: t()
  def new(root, opts \\ []) do
    File.mkdir_p!(root)

    %__MODULE__{
      root: root,
      max_bytes: Keyword.get(opts, :max_bytes, 1_048_576),
      max_age_ms: Keyword.get(opts, :max_age_ms, 30_000),
      manifest_name: Keyword.get(opts, :manifest_name, "manifest.json"),
      current_started_at_ms: monotonic_ms()
    }
  end

  @spec append(t(), map(), keyword()) :: {t(), [map()]}
  def append(%__MODULE__{} = writer, event, opts \\ []) when is_map(event) do
    line = Jason.encode!(event) <> "\n"
    now_ms = Keyword.get(opts, :now_ms, monotonic_ms())

    {writer, flushed} =
      if flush_before_append?(writer, byte_size(line), now_ms) do
        flush(writer)
      else
        {writer, []}
      end

    writer = %{
      writer
      | current_lines: writer.current_lines ++ [line],
        current_bytes: writer.current_bytes + byte_size(line)
    }

    {writer, flushed}
  end

  @spec close(t()) :: {t(), [map()]}
  def close(%__MODULE__{} = writer) do
    {writer, flushed} = flush(writer)
    write_manifest!(writer)
    {writer, flushed}
  end

  defp flush_before_append?(%__MODULE__{current_lines: []}, _line_bytes, _now_ms), do: false

  defp flush_before_append?(%__MODULE__{} = writer, line_bytes, now_ms) do
    writer.current_bytes + line_bytes > writer.max_bytes or
      now_ms - writer.current_started_at_ms >= writer.max_age_ms
  end

  defp flush(%__MODULE__{current_lines: []} = writer), do: {writer, []}

  defp flush(%__MODULE__{} = writer) do
    body = Enum.join(writer.current_lines, "")
    path = "segments/#{segment_name(writer.next_segment)}"
    absolute_path = Path.join(writer.root, path)
    File.mkdir_p!(Path.dirname(absolute_path))
    File.write!(absolute_path, body)

    events = Enum.map(writer.current_lines, &Jason.decode!/1)

    segment = %{
      "path" => path,
      "bytes" => byte_size(body),
      "digest" => sha256(body),
      "sequence_start" => events |> List.first() |> Map.fetch!("sequence"),
      "sequence_end" => events |> List.last() |> Map.fetch!("sequence")
    }

    writer = %{
      writer
      | current_lines: [],
        current_bytes: 0,
        current_started_at_ms: monotonic_ms(),
        next_segment: writer.next_segment + 1,
        segments: writer.segments ++ [segment]
    }

    {writer, [segment]}
  end

  defp write_manifest!(%__MODULE__{} = writer) do
    manifest = %{
      "schema_version" => "conveyor.event_segment_manifest@1",
      "segments" => writer.segments
    }

    File.write!(
      Path.join(writer.root, writer.manifest_name),
      Jason.encode!(manifest, pretty: true)
    )
  end

  defp segment_name(index),
    do: index |> Integer.to_string() |> String.pad_leading(6, "0") |> Kernel.<>(".jsonl")

  defp sha256(body), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, body), case: :lower)

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
