defmodule Conveyor.Planning.WorkGraphLowering do
  @moduledoc """
  Lowers a selected decomposition proposal to `conveyor.work_graph@2` IR.

  Lowering is intentionally all-or-nothing: invalid proposal shape or a stale
  PlanningSpec digest returns diagnostics and no materialized WorkGraph.
  """

  @candidate_schema "conveyor.decomposition_candidate@1"
  @work_graph_schema "conveyor.work_graph@2"

  @spec lower(map(), map()) :: {:ok, map()} | {:error, map()}
  def lower(candidate, planning_spec) when is_map(candidate) and is_map(planning_spec) do
    errors = validation_errors(candidate, planning_spec)

    if errors == [] do
      {:ok, build_graph(candidate, planning_spec)}
    else
      {:error,
       %{
         status: :invalid_proposal,
         errors: errors,
         work_graph: nil
       }}
    end
  end

  defp build_graph(candidate, planning_spec) do
    %{
      schema_version: @work_graph_schema,
      plan_revision_digest: value(planning_spec, :plan_revision_digest),
      constraint_set_digest: value(planning_spec, :constraint_set_digest),
      selected_candidate_digest: digest(candidate),
      claim_set_ref: value(candidate, :claim_set_ref),
      epics: normalize_list(value(candidate, :epics)),
      atomicity_groups: normalize_list(value(candidate, :atomicity_groups)),
      slices: normalize_list(value(candidate, :slices)),
      work_dependencies: normalize_list(value(candidate, :work_deps)),
      interface_contracts: normalize_list(value(candidate, :interface_contracts)),
      interface_bindings: normalize_list(value(candidate, :interface_bindings)),
      decision_blocks: normalize_list(value(candidate, :decision_blocks)),
      constraint_status: normalize_list(value(candidate, :constraint_status) || []),
      scope_delta: value(candidate, :scope_delta),
      derivation_manifest_ref: value(candidate, :derivation_manifest_ref)
    }
  end

  defp validation_errors(candidate, planning_spec) do
    []
    |> require_equal(
      value(candidate, :schema_version),
      @candidate_schema,
      "schema_version must be #{@candidate_schema}"
    )
    |> require_equal(
      value(candidate, :planning_spec_digest),
      value(planning_spec, :spec_digest),
      "planning_spec_digest does not match frozen PlanningSpec"
    )
    |> require_equal(value(planning_spec, :status), :frozen, "PlanningSpec must be frozen")
    |> require_present(candidate, :candidate_key)
    |> require_present(candidate, :claim_set_ref)
    |> require_present(candidate, :derivation_manifest_ref)
    |> require_present(candidate, :scope_delta)
    |> require_list(candidate, :epics)
    |> require_list(candidate, :slices)
    |> require_list(candidate, :atomicity_groups)
    |> require_list(candidate, :work_deps)
    |> require_list(candidate, :interface_contracts)
    |> require_list(candidate, :interface_bindings)
    |> require_list(candidate, :decision_blocks)
    |> validate_slices(candidate)
  end

  defp validate_slices(errors, candidate) do
    candidate
    |> value(:slices)
    |> case do
      slices when is_list(slices) ->
        slices
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {slice, index}, acc ->
          acc
          |> require_present(slice, :stable_key, "slices[#{index}].stable_key is required")
          |> require_present(slice, :proposal_key, "slices[#{index}].proposal_key is required")
          |> require_present(slice, :title, "slices[#{index}].title is required")
          |> require_present(slice, :why_this_slice, "slices[#{index}].why_this_slice is required")
        end)

      _other ->
        errors
    end
  end

  defp require_equal(errors, actual, expected, message) do
    if actual == expected, do: errors, else: errors ++ [message]
  end

  defp require_present(errors, map, key, message \\ nil) do
    message = message || "#{key} is required"

    case value(map, key) do
      nil -> errors ++ [message]
      "" -> errors ++ [message]
      [] -> errors ++ [message]
      _value -> errors
    end
  end

  defp require_list(errors, map, key) do
    if is_list(value(map, key)), do: errors, else: errors ++ ["#{key} must be a list"]
  end

  defp normalize_list(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_list(_value), do: []

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value

  defp value(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp digest(value) do
    "sha256:" <>
      (value
       |> canonical_json()
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end

  defp canonical_json(%{} = map) do
    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(values) when is_list(values),
    do: "[" <> Enum.map_join(values, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
