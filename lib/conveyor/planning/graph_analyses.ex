defmodule Conveyor.Planning.GraphAnalyses do
  @moduledoc """
  Pure graph analyses for P2-A3 compiler output.
  """

  @spec run(map()) :: map()
  def run(input) when is_map(input) do
    graph = normalize_value(input)

    findings =
      []
      |> Kernel.++(atomicity_findings(graph))
      |> Kernel.++(scope_findings(graph))
      |> Kernel.++(traceability_findings(graph))
      |> Kernel.++(anti_confetti_findings(graph))
      |> Kernel.++(oracle_findings(graph))

    %{
      status: if(findings == [], do: :passed, else: :blocked),
      scope_delta: if(scope_findings(graph) == [], do: :scope_preserved, else: :scope_expanded),
      findings: findings
    }
  end

  defp atomicity_findings(graph) do
    slice_keys = graph |> list(:slices) |> MapSet.new(& &1.stable_key)

    graph
    |> list(:atomicity_groups)
    |> Enum.flat_map(fn group ->
      group
      |> list(:member_keys)
      |> Enum.reject(&MapSet.member?(slice_keys, &1))
      |> Enum.map(&finding("atomicity_group_missing_member", "#{group.key} -> #{&1}"))
    end)
  end

  defp scope_findings(graph) do
    approved = list(graph, :approved_scope_globs)

    graph
    |> list(:slices)
    |> Enum.flat_map(fn slice ->
      slice
      |> list(:authorized_change_globs)
      |> Enum.reject(&approved_scope?(&1, approved))
      |> Enum.map(&finding("unapproved_scope_delta", "#{slice.stable_key} -> #{&1}"))
    end)
  end

  defp traceability_findings(graph) do
    ac_keys = graph |> list(:acceptance_criteria) |> MapSet.new(& &1.key)
    obligation_ac_keys = graph |> list(:obligations) |> MapSet.new(&value(&1, :acceptance_ref))

    graph
    |> list(:slices)
    |> Enum.flat_map(fn slice ->
      cond do
        list(slice, :requirement_refs) == [] ->
          [finding("traceability_gap", "#{slice.stable_key} has no requirement")]

        list(slice, :acceptance_refs) == [] ->
          [finding("traceability_gap", "#{slice.stable_key} has no acceptance criteria")]

        Enum.any?(list(slice, :acceptance_refs), &(not MapSet.member?(ac_keys, &1))) ->
          [finding("traceability_gap", "#{slice.stable_key} references unknown acceptance")]

        Enum.any?(list(slice, :acceptance_refs), &(not MapSet.member?(obligation_ac_keys, &1))) ->
          [finding("traceability_gap", "#{slice.stable_key} has no obligation")]

        true ->
          []
      end
    end)
  end

  defp anti_confetti_findings(graph) do
    slices = list(graph, :slices)
    deps = list(graph, :work_dependencies)

    too_small =
      slices
      |> Enum.filter(&(list(&1, :acceptance_refs) == []))
      |> Enum.map(&finding("slice_too_small", &1.stable_key))

    coordination =
      if length(deps) > length(slices) do
        [finding("coordination_overhead", "work_dependencies")]
      else
        []
      end

    false_parallelism =
      if Enum.any?(deps, &(&1.from == &1.to)) do
        [finding("false_parallelism", "self_dependency")]
      else
        []
      end

    risk_domains =
      slices
      |> Enum.filter(&(length(list(&1, :risk_domains)) > 3))
      |> Enum.map(&finding("risk_domains", &1.stable_key))

    too_small ++ coordination ++ false_parallelism ++ risk_domains
  end

  defp oracle_findings(graph) do
    graph
    |> list(:slices)
    |> Enum.filter(&(value(&1, :oracle_feasible?) == false))
    |> Enum.map(&finding("oracle_infeasible", &1.stable_key))
  end

  defp finding(rule_key, subject_key) do
    %{
      rule_key: rule_key,
      severity: :blocking,
      subject_key: subject_key
    }
  end

  defp approved_scope?(glob, approved_globs) do
    Enum.any?(approved_globs, fn approved ->
      approved == glob or
        (String.ends_with?(approved, "/**") and
           String.starts_with?(glob, String.replace_suffix(approved, "/**", "/")))
    end)
  end

  defp list(map, key), do: value(map, key) || []

  defp value(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, to_string(key)) -> Map.get(map, to_string(key))
      true -> nil
    end
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
