defmodule Conveyor.Planning.ImpactPreview do
  @moduledoc """
  Operator-facing deterministic impact preview projection.
  """

  alias Conveyor.Evidence.InvalidationPreview

  @schema_version "conveyor.planning_impact_preview@1"

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    invalidation = InvalidationPreview.preview_invalidation(input)
    affected = invalidation["affected_subjects"]

    projection = %{
      "schema_version" => @schema_version,
      "change_set_id" => invalidation["change_set_id"],
      "status" => invalidation["confidence_status"],
      "fail_wide" => invalidation["fail_wide"],
      "impact_confidence" => invalidation["impact_confidence"],
      "new_snapshot_revision" => value(input, :next_revision_id),
      "invalidated_approvals" =>
        subjects_for_actions(affected, ["reapprove_epic", "reapprove_shared_root"]),
      "regenerated_contracts" => subjects_for_actions(affected, ["regenerate_contract"]),
      "regenerated_interfaces" => subjects_for_actions(affected, ["recompile_prompt"]),
      "revalidated_test_packs" => subjects_matching(affected, "test_pack:"),
      "revalidated_obligations" =>
        subjects_for_actions(affected, ["regenerate_verification_obligations"]),
      "reusable_locks" => sorted_strings(input, :reusable_locks),
      "new_run_specs" => sorted_strings(input, :new_run_specs),
      "grant_impact" => grant_impacts(input),
      "operator_warnings" => operator_warnings(invalidation)
    }

    Map.put(projection, "preview_digest", digest(projection))
  end

  defp subjects_for_actions(affected, actions) do
    affected
    |> Enum.filter(&(&1["action"] in actions))
    |> Enum.map(& &1["subject_ref"])
    |> Enum.sort()
  end

  defp subjects_matching(affected, prefix) do
    affected
    |> Enum.map(& &1["subject_ref"])
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.sort()
  end

  defp operator_warnings(%{"fail_wide" => true}), do: ["impact_confidence_low"]
  defp operator_warnings(_invalidation), do: []

  defp grant_impacts(input) do
    input
    |> list(:grant_impacts)
    |> Enum.map(fn impact ->
      %{
        "grant_id" => value(impact, :grant_id),
        "action" => value(impact, :action)
      }
    end)
    |> Enum.sort_by(fn impact -> {impact["grant_id"], impact["action"]} end)
  end

  defp sorted_strings(input, key) do
    input
    |> list(key)
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
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

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
