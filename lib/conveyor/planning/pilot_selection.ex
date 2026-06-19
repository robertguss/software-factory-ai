defmodule Conveyor.Planning.PilotSelection do
  @moduledoc """
  Freezes pre-registered pilot selection before implementation starts.
  """

  @schema_version "conveyor.pilot_selection@1"
  @required_coverage_classes ~w(
    root_slice
    terminal_slice
    dependency_pair
    fork_join
    public_interface
    migration_compatibility
    low_risk
    high_risk
    parked_path
    human_verification
    unchanged_contract
    amendment_path
    alternative_candidate
  )

  @spec required_coverage_classes() :: [String.t()]
  def required_coverage_classes, do: @required_coverage_classes

  @spec freeze(map()) :: map()
  def freeze(input) when is_map(input) do
    if value(input, :implementation_started?) == true do
      %{
        "status" => "blocked",
        "blocking_reasons" => ["implementation_already_started"],
        "pilot_selection" => nil
      }
    else
      build_selection(input)
    end
  end

  defp build_selection(input) do
    plan = value(input, :plan)
    selected_slice_ids = selected_slice_ids(plan)

    base = %{
      "schema_version" => @schema_version,
      "planning_bundle_id" => value(input, :planning_bundle_id),
      "selection_policy_digest" => digest_ref(selection_policy(plan)),
      "selected_slice_ids" => selected_slice_ids,
      "required_coverage_classes" => @required_coverage_classes,
      "excluded_slice_ids_with_reasons" =>
        excluded_slice_ids_with_reasons(plan, selected_slice_ids),
      "frozen_at" => value(input, :frozen_at)
    }

    Map.put(base, "selection_digest", digest_ref(base))
  end

  defp selected_slice_ids(plan) do
    slices = list(plan, :slices)

    if length(slices) <= 12 do
      slices
      |> Enum.filter(&value(&1, :machine_executable))
      |> Enum.map(&value(&1, :slice_id))
      |> Enum.sort()
    else
      coverage_sample_slice_ids(slices)
    end
  end

  defp coverage_sample_slice_ids(slices) do
    slices
    |> Enum.filter(fn slice ->
      slice
      |> list(:coverage_classes)
      |> Enum.any?(&(&1 in @required_coverage_classes))
    end)
    |> Enum.map(&value(&1, :slice_id))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp excluded_slice_ids_with_reasons(plan, selected_slice_ids) do
    selected = MapSet.new(selected_slice_ids)

    plan
    |> list(:slices)
    |> Enum.filter(&(value(&1, :machine_executable) == true))
    |> Enum.reject(&MapSet.member?(selected, value(&1, :slice_id)))
    |> Enum.map(fn slice ->
      %{
        "slice_id" => value(slice, :slice_id),
        "reason" => "outside_versioned_coverage_sample"
      }
    end)
    |> Enum.sort_by(& &1["slice_id"])
  end

  defp selection_policy(plan) do
    %{
      "policy" =>
        if(length(list(plan, :slices)) <= 12,
          do: "all_machine_executable",
          else: "coverage_sample"
        ),
      "required_coverage_classes" => @required_coverage_classes
    }
  end

  defp digest_ref(value) do
    %{
      "schema_version" => "conveyor.digest_ref@1",
      "algorithm" => "sha256",
      "value" =>
        value
        |> canonical_json()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
    }
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

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))
end
