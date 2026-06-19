defmodule Conveyor.Evidence.TimeMachine do
  @moduledoc """
  DB-free Evidence Time Machine projections for CLI commands.

  Inputs are already-resolved subject descriptors. The module emits
  machine-readable reports that can later be backed by richer stores without
  changing CLI output shape.
  """

  alias Conveyor.Evidence.Comparator

  @spec diff(String.t(), map(), map(), keyword()) :: map()
  def diff(command, left, right, opts \\ [])
      when is_binary(command) and is_map(left) and is_map(right) and is_list(opts) do
    comparison =
      left
      |> Comparator.compare(right, Keyword.take(opts, [:materiality_labels]))
      |> stringify_keys()

    %{
      "schema_version" => "conveyor.evidence_time_machine.diff@1",
      "command" => command,
      "section" => Keyword.get(opts, :section),
      "canonical_json" => true,
      "comparison" => comparison
    }
    |> maybe_put_markdown(Keyword.get(opts, :markdown))
  end

  @spec read_json!(Path.t()) :: map()
  def read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  @spec why_stale(map()) :: map()
  def why_stale(subject) when is_map(subject) do
    reasons = Map.get(subject, "stale_reasons", Map.get(subject, :stale_reasons, []))

    %{
      "schema_version" => "conveyor.evidence_time_machine.why_stale@1",
      "subject_id" => Map.get(subject, "subject_id", Map.get(subject, :subject_id)),
      "stale" => reasons != [],
      "reasons" => reasons,
      "canonical_json" => true
    }
  end

  defp maybe_put_markdown(report, nil), do: report

  defp maybe_put_markdown(report, markdown) do
    Map.put(report, "markdown", markdown)
  end

  defp stringify_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(values) when is_list(values), do: Enum.map(values, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
