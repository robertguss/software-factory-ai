defmodule Conveyor.ContextGroundTruth do
  @moduledoc """
  Context-ground-truth and proxy metric evaluator.

  Precision/recall are reported only for labelled Battery fixtures that provide
  necessary/useful/forbidden source references. Unlabelled work emits only the
  explicit proxy metrics named in the plan.
  """

  @schema_version "conveyor.context_ground_truth_report@1"

  @spec evaluate(map()) :: map()
  def evaluate(attrs) when is_map(attrs) do
    labelled? = labelled?(attrs)

    %{
      "schema_version" => @schema_version,
      "case_id" => value(attrs, :case_id),
      "labelled" => labelled?,
      "selected_context_precision" => if(labelled?, do: selected_precision(attrs), else: nil),
      "necessary_context_recall" => if(labelled?, do: necessary_recall(attrs), else: nil),
      "forbidden_selected_refs" => if(labelled?, do: forbidden_selected_refs(attrs), else: []),
      "proxy_metrics" => proxy_metrics(attrs)
    }
  end

  defp labelled?(attrs) do
    list(attrs, :necessary_source_refs) != [] or list(attrs, :useful_source_refs) != [] or
      list(attrs, :forbidden_or_irrelevant_source_refs) != []
  end

  defp selected_precision(attrs) do
    selected = MapSet.new(list(attrs, :selected_source_refs))
    relevant = MapSet.new(list(attrs, :necessary_source_refs) ++ list(attrs, :useful_source_refs))

    ratio(MapSet.size(MapSet.intersection(selected, relevant)), MapSet.size(selected))
  end

  defp necessary_recall(attrs) do
    selected = MapSet.new(list(attrs, :selected_source_refs))
    necessary = MapSet.new(list(attrs, :necessary_source_refs))

    ratio(MapSet.size(MapSet.intersection(selected, necessary)), MapSet.size(necessary))
  end

  defp forbidden_selected_refs(attrs) do
    selected = MapSet.new(list(attrs, :selected_source_refs))

    attrs
    |> list(:forbidden_or_irrelevant_source_refs)
    |> Enum.filter(&MapSet.member?(selected, &1))
    |> Enum.sort()
  end

  defp proxy_metrics(attrs) do
    selected = MapSet.new(list(attrs, :selected_source_refs))
    patch = MapSet.new(list(attrs, :patch_source_refs))

    %{
      "selected_context_used_by_patch" => not MapSet.disjoint?(selected, patch),
      "files_opened_but_unused" => opened_but_unused(attrs),
      "post_failure_missing_context" => value(attrs, :post_failure_missing_context, false),
      "budget_exhausted" => value(attrs, :budget_exhausted, false),
      "critical_context_shed" => value(attrs, :critical_context_shed, false)
    }
  end

  defp opened_but_unused(attrs) do
    patch = MapSet.new(list(attrs, :patch_source_refs))

    attrs
    |> list(:opened_source_refs)
    |> Enum.reject(&MapSet.member?(patch, &1))
    |> Enum.sort()
  end

  defp ratio(_numerator, 0), do: nil
  defp ratio(numerator, denominator), do: numerator / denominator

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)

    Map.get(map, key, Map.get(map, string_key, default))
  end
end
