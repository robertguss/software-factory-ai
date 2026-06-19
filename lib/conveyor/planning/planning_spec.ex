defmodule Conveyor.Planning.PlanningSpec do
  @moduledoc """
  Immutable planning execution capsule for Phase 2 planning.
  """

  @spec build!(map()) :: map()
  def build!(attrs) when is_map(attrs) do
    normalized = normalize_keys(attrs)
    pass_graph = Map.fetch!(normalized, "pass_graph")

    spec =
      normalized
      |> Map.put("pass_graph_digest", digest(pass_graph))
      |> Map.put("status", :frozen)

    spec
    |> Map.put("spec_digest", digest(spec))
    |> atomize_top_level()
  end

  @spec override!(map(), map()) :: no_return()
  def override!(%{status: :frozen}, _attrs) do
    raise ArgumentError, "frozen PlanningSpec is immutable; create a new PlanningSpec"
  end

  defp normalize_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_keys(value)} end)
  end

  defp normalize_keys(values) when is_list(values), do: Enum.map(values, &normalize_keys/1)
  defp normalize_keys(value) when is_atom(value), do: value
  defp normalize_keys(value), do: value

  defp atomize_top_level(%{} = map) do
    Map.new(map, fn {key, value} -> {String.to_atom(key), atomize_top_level(value)} end)
  end

  defp atomize_top_level(values) when is_list(values), do: Enum.map(values, &atomize_top_level/1)
  defp atomize_top_level(value), do: value

  defp digest(value) do
    "sha256:" <>
      (value
       |> canonical_json()
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
