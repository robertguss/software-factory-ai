defmodule Conveyor.Planning.PlanWarnings do
  @moduledoc """
  Plan-lint WARNINGS engine (a3hf.2.2.1): surfaces the compiler's existing structural
  and work-graph audits as non-blocking advisories for the plan preview / dry-run —
  dependency cycles, orphan (unreachable) slices, untestable/empty acceptance criteria,
  and unlocked public interfaces.

  Every item is `severity: :warning` — this is a preview aid, not a gate. The blocking
  contract gate lives in `Conveyor.Planning.PlanLint`.
  """

  alias Conveyor.Planning.ScopeCap
  alias Conveyor.Planning.SliceDependency
  alias Conveyor.Planning.StructuralAudit

  @acceptance_rules ~w(unmeasurable_acceptance missing_oracle_path missing_requirement_acceptance)

  @spec warn(map(), map()) :: [map()]
  def warn(contract, work_graph \\ %{}) when is_map(contract) and is_map(work_graph) do
    graph_warnings(work_graph) ++
      scope_bound_warnings(work_graph) ++
      acceptance_warnings(contract) ++ interface_warnings(contract)
  end

  # nyrl.3: a slice whose declared scope already exceeds the profile bound is an authoring
  # smell surfaced BEFORE the run, not a 2am park.
  defp scope_bound_warnings(work_graph) do
    work_graph
    |> list("slices")
    |> Enum.filter(fn slice ->
      ScopeCap.over_declared_bound?(length(list(slice, "likely_files")))
    end)
    |> Enum.map(fn slice ->
      key = value(slice, "stable_key")
      declared = length(list(slice, "likely_files"))

      warning(
        "scope_exceeds_bound",
        key,
        "Slice #{key} declares #{declared} files, over the #{ScopeCap.max_declared_files()}-file bound — split it."
      )
    end)
  end

  defp graph_warnings(work_graph) do
    work_graph
    |> SliceDependency.analyze()
    |> Map.get(:diagnostics, [])
    |> Enum.flat_map(&List.wrap(graph_warning(&1)))
  end

  defp graph_warning(%{rule_key: "work_graph_cycle", subject_key: subject}),
    do: warning("dependency_cycle", subject, "Slice dependencies form a cycle: #{subject}.")

  defp graph_warning(%{rule_key: "unreachable_active_slice", subject_key: subject}),
    do:
      warning(
        "orphan_slice",
        subject,
        "Active slice #{subject} is unreachable in the work graph."
      )

  defp graph_warning(_other), do: nil

  defp acceptance_warnings(contract) do
    contract
    |> StructuralAudit.audit()
    |> Map.get(:findings, [])
    |> Enum.filter(&(&1.rule_key in @acceptance_rules))
    |> Enum.map(&warning("untestable_acceptance", &1.subject_key, &1.message))
  end

  defp interface_warnings(contract) do
    contract
    |> list("interfaces")
    |> Enum.reject(&interface_locked?/1)
    |> Enum.map(fn interface ->
      key = value(interface, "key")

      warning(
        "unlocked_interface",
        key,
        "Public interface #{key} is not locked (missing version or schema_ref)."
      )
    end)
  end

  defp interface_locked?(interface),
    do: present?(value(interface, "version")) and present?(value(interface, "schema_ref"))

  defp warning(rule_key, subject_key, message),
    do: %{rule_key: rule_key, severity: :warning, subject_key: subject_key, message: message}

  defp list(map, key), do: value(map, key) || []

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, safe_atom(key)))

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :"#{key}__absent"
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
