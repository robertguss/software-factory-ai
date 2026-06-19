defmodule Conveyor.Planning.WorkbenchViews do
  @moduledoc """
  Core read-only Plan Workbench view projection.
  """

  @schema_version "conveyor.plan_workbench_views@1"
  @view_order ~w(
    claims
    constraints
    candidates
    work_graph
    interfaces
    decision_blocks
    obligations
    derivations
    diffs
    approvals
  )
  @lanes ~w(intent traceability risk_recovery code_impact)
  @default_lanes %{
    "claims" => "intent",
    "constraints" => "intent",
    "candidates" => "risk_recovery",
    "work_graph" => "traceability",
    "interfaces" => "traceability",
    "decision_blocks" => "risk_recovery",
    "obligations" => "traceability",
    "derivations" => "traceability",
    "diffs" => "code_impact",
    "approvals" => "risk_recovery"
  }

  @spec project(map()) :: map()
  def project(input) when is_map(input) do
    views = Map.new(@view_order, &{&1, view(input, &1)})

    projection = %{
      "schema_version" => @schema_version,
      "authority_effect" => "none",
      "view_order" => @view_order,
      "views" => views,
      "lanes" => lanes(views)
    }

    Map.put(projection, "projection_digest", digest(projection))
  end

  defp view(input, name) do
    items =
      input
      |> value(String.to_atom(name), [])
      |> list()
      |> Enum.map(&with_default_lane(&1, name))
      |> Enum.sort_by(&value(&1, :id, ""))

    %{
      "items" => items,
      "count" => length(items)
    }
  end

  defp with_default_lane(item, view_name) do
    item
    |> stringify_value()
    |> Map.put_new("lane", Map.fetch!(@default_lanes, view_name))
  end

  defp lanes(views) do
    Map.new(@lanes, fn lane ->
      ids =
        views
        |> Enum.flat_map(fn {_view_name, view} -> view["items"] end)
        |> Enum.filter(&(value(&1, :lane) == lane))
        |> Enum.map(&value(&1, :id))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort()

      {lane, ids}
    end)
  end

  defp list(values) when is_list(values), do: values
  defp list(nil), do: []
  defp list(value), do: [value]

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

  defp stringify_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), stringify_value(nested)} end)
  end

  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
