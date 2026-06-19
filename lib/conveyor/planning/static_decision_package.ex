defmodule Conveyor.Planning.StaticDecisionPackage do
  @moduledoc """
  Static, non-authorizing compiler decision package.
  """

  @required_artifacts [
    :normalized_plan,
    :claims,
    :constraints,
    :candidate_comparison,
    :work_graph,
    :interfaces,
    :decisions,
    :derivation_graph,
    :structural_dry_run,
    :scope_delta,
    :oracle_warnings
  ]

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    normalized = normalize_value(input)
    missing = Enum.reject(@required_artifacts, &Map.has_key?(normalized, &1))

    if missing == [] do
      artifacts = Map.take(normalized, @required_artifacts)

      %{
        status: :complete,
        package_kind: :static_decision_package,
        authority_effect: :none,
        creates_contract_lock?: false,
        creates_approval?: false,
        creates_ready_slice?: false,
        artifacts: artifacts,
        artifact_digest: digest(artifacts)
      }
    else
      %{
        status: :blocked,
        package_kind: :static_decision_package,
        authority_effect: :none,
        artifacts: nil,
        missing_artifacts: Enum.map(missing, &Atom.to_string/1)
      }
    end
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value

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
