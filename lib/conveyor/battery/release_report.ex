defmodule Conveyor.Battery.ReleaseReport do
  @moduledoc """
  Canonical P15-B5 release report projection.

  Source summaries are advisory text. Failed and excluded cases remain structured
  fields so summaries cannot hide canonical blockers.
  """

  @schema_version "conveyor.battery_release_report@1"

  @spec build([map()]) :: map()
  def build(sources) when is_list(sources) do
    normalized_sources = Enum.map(sources, &normalize_source/1)

    %{
      "schema_version" => @schema_version,
      "complete?" => true,
      "source_count" => length(normalized_sources),
      "sources" => normalized_sources,
      "canonical_blockers" => flatten_cases(normalized_sources, "failed_cases"),
      "excluded_cases" => flatten_cases(normalized_sources, "excluded_cases")
    }
  end

  defp normalize_source(source) do
    %{
      "source_id" => value(source, :source_id),
      "summary" => value(source, :summary),
      "failed_cases" => Enum.map(list(source, :failed_cases), &normalize_case/1),
      "excluded_cases" => Enum.map(list(source, :excluded_cases), &normalize_case/1)
    }
  end

  defp normalize_case(case_entry) do
    %{
      "case_id" => value(case_entry, :case_id),
      "reason" => value(case_entry, :reason)
    }
  end

  defp flatten_cases(sources, key) do
    Enum.flat_map(sources, fn source ->
      Enum.map(source[key], fn case_entry ->
        Map.put(case_entry, "source_id", source["source_id"])
      end)
    end)
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
