defmodule Conveyor.TestArchitect.ContractAudit do
  @moduledoc """
  Dimensional ContractAudit report builder.

  Contract quality readiness is reported per dimension and per stage. The
  projection intentionally has no aggregate score.
  """

  @decisions ~w(ready needs_revision blocked human_verification_required)
  @dimension_statuses ~w(passed needs_revision blocked not_assessed human_verification_required)
  @required_dimensions ~w(traceability claim_and_source_anchor_coverage scope_boundedness interface_clarity interface_compatibility dependency_clarity atomicity_safety acceptance_falsifiability)

  @spec report!(map()) :: map()
  def report!(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)

    audit =
      %{
        "schema_version" => "conveyor.contract_audit@1",
        "slice_id" => required_string(normalized, "slice_id"),
        "agent_brief_id" => required_string(normalized, "agent_brief_id"),
        "test_pack_id" => optional_string(normalized, "test_pack_id"),
        "planning_run_id" => optional_string(normalized, "planning_run_id"),
        "compiler_version" => required_string(normalized, "compiler_version"),
        "decision" => required_enum(normalized, "decision", @decisions),
        "stages" =>
          normalized
          |> required_list("stages")
          |> Enum.map(&stage!/1),
        "quality_dimensions" => quality_dimensions!(Map.fetch!(normalized, "quality_dimensions")),
        "report_ref" => required_string(normalized, "report_ref")
      }

    digest = digest(audit)

    audit
    |> Map.put("contract_audit_digest", "sha256:#{digest}")
    |> Map.put("id", "contract_audit:sha256:#{digest}")
  end

  defp quality_dimensions!(dimensions) when is_map(dimensions) do
    normalized = stringify_map(dimensions)

    for dimension <- @required_dimensions, into: %{} do
      {dimension, required_enum(normalized, dimension, @dimension_statuses)}
    end
  end

  defp quality_dimensions!(_dimensions),
    do: raise(ArgumentError, "quality_dimensions must be a map")

  defp stage!(stage) when is_map(stage) do
    normalized = stringify_map(stage)

    %{
      "key" => required_string(normalized, "key"),
      "status" => required_enum(normalized, "status", @dimension_statuses),
      "finding_refs" => optional_string_list(normalized, "finding_refs")
    }
  end

  defp stage!(_stage), do: raise(ArgumentError, "stage must be a map")

  defp required_enum(map, key, allowed) do
    value = required_string(map, key)

    if value in allowed do
      value
    else
      raise ArgumentError, "#{key} must be one of #{Enum.join(allowed, ", ")}"
    end
  end

  defp required_list(map, key) do
    case Map.fetch!(map, key) do
      values when is_list(values) and values != [] -> values
      [] -> raise ArgumentError, "#{key} must not be empty"
      _other -> raise ArgumentError, "#{key} must be a list"
    end
  end

  defp optional_string_list(map, key) do
    case Map.get(map, key, []) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          values
        else
          raise ArgumentError, "#{key} must contain only non-empty strings"
        end

      _other ->
        raise ArgumentError, "#{key} must be a list"
    end
  end

  defp required_string(map, key) do
    case Map.fetch!(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp optional_string(map, key) do
    case Map.get(map, key) do
      nil -> nil
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be nil or a non-empty string"
    end
  end

  defp digest(value) do
    value
    |> canonical_term()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> stringify_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [key, canonical_term(value)] end)
  end

  defp canonical_term(values) when is_list(values), do: Enum.map(values, &canonical_term/1)
  defp canonical_term(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
