defmodule Conveyor.Planning.SelectiveInvalidation do
  @moduledoc """
  Classifies selective invalidation outcomes for amendment changes.
  """

  @spec classify(map()) :: map()
  def classify(input) when is_map(input) do
    outcomes =
      input
      |> list(:changes)
      |> Enum.flat_map(&change_outcomes/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort_by(&{&1["subject_ref"], &1["action"], &1["reason"]})

    %{
      "outcomes" => outcomes,
      "preserved_locks" => preserved_locks(outcomes)
    }
  end

  defp change_outcomes(change) do
    case value(change, :change_kind) do
      "shared_interface" ->
        change
        |> list(:affected_consumers)
        |> Enum.map(&outcome(&1, "invalidate_downstream_attempt", "shared_interface_changed"))

      "review_only_correction" ->
        [outcome(value(change, :subject_ref), "unchanged_reusable", "review_only_correction")]

      "waiver_change" ->
        [
          outcome(value(change, :obligation_ref), "invalidate_obligation", "waiver_changed"),
          outcome(value(change, :epic_ref), "requalify_scope", "waiver_changed"),
          outcome(value(change, :grant_id), "requalify_scope", "waiver_changed")
        ]

      _other ->
        []
    end
  end

  defp preserved_locks(outcomes) do
    outcomes
    |> Enum.filter(&(&1["action"] == "unchanged_reusable"))
    |> Enum.map(& &1["subject_ref"])
    |> Enum.filter(&String.starts_with?(&1, "contract_lock:"))
    |> Enum.sort()
  end

  defp outcome(nil, _action, _reason), do: nil

  defp outcome(subject_ref, action, reason) do
    %{"subject_ref" => subject_ref, "action" => action, "reason" => reason}
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))
end
