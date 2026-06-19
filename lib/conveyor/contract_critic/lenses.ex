defmodule Conveyor.ContractCritic.Lenses do
  @moduledoc """
  Pure multi-lens Contract Critic projection.

  Critic lenses may challenge contracts and preserve disagreement, but they
  never approve, lock, or grant implementation authority.
  """

  @required_lenses ~w(
    intent_fidelity
    scope_delta
    principal_engineering
    interface_compatibility
    test_loopholes
    reliability_observability
    security
    cost_simplification
    hidden_decision
    approval_cognitive_load
  )

  @spec required_lenses() :: [String.t()]
  def required_lenses, do: @required_lenses

  @spec review(map()) :: map()
  def review(input) when is_map(input) do
    normalized = stringify_map(input)
    lens_inputs = Map.get(normalized, "lens_inputs", %{})

    lens_results = Enum.map(@required_lenses, &lens_result(&1, lens_inputs))

    %{
      authority_effect: :none,
      can_approve?: false,
      can_lock?: false,
      contract_id: Map.fetch!(normalized, "contract_id"),
      evidence_refs: Map.get(normalized, "evidence_refs", []),
      lens_results: lens_results,
      disagreements: disagreements(lens_inputs),
      overall_status: overall_status(lens_results)
    }
  end

  defp lens_result(lens, lens_inputs) do
    input = Map.get(lens_inputs, lens, %{})

    %{
      "lens" => lens,
      "status" => Map.get(input, "status", "pass"),
      "findings" => Map.get(input, "findings", [])
    }
  end

  defp disagreements(lens_inputs) when map_size(lens_inputs) == 0, do: []

  defp disagreements(lens_inputs) do
    statuses =
      lens_inputs
      |> Map.values()
      |> Enum.map(&Map.get(&1, "status", "pass"))
      |> Enum.uniq()
      |> Enum.sort()

    if Enum.count(statuses) > 1 do
      [%{"status_set" => statuses, "lenses" => lens_inputs |> Map.keys() |> Enum.sort()}]
    else
      []
    end
  end

  defp overall_status(lens_results) do
    if Enum.any?(lens_results, &(&1["status"] == "fail")) do
      :challenged
    else
      :passed
    end
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
