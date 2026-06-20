defmodule Conveyor.ContractForge.FalsifierForge do
  @moduledoc """
  Builds the pre-agent red-on-base falsifier report for a locked slice contract.
  """

  alias Conveyor.ContractForge.FalsifierSeedDeriver

  @schema_version "conveyor.falsifier_forge@1"

  @spec run!([map()], [map()] | nil) :: map()
  def run!(acceptance_criteria, seeds \\ nil) when is_list(acceptance_criteria) do
    criteria = Enum.map(acceptance_criteria, &stringify_map/1)
    seeds = seeds || FalsifierSeedDeriver.derive!(%{"acceptance_criteria" => criteria})
    seeds_by_ac = Enum.group_by(seeds, & &1["source_acceptance_criterion_id"])

    rows = Enum.map(criteria, &criterion_row(&1, seeds_by_ac))
    missing = Enum.filter(rows, &(&1["seed_ids"] == [] or &1["required_test_refs"] == []))

    if missing != [] do
      ids = Enum.map_join(missing, ", ", & &1["id"])
      raise ArgumentError, "falsifier forge missing red-on-base coverage for #{ids}"
    end

    %{
      "schema_version" => @schema_version,
      "status" => "passed",
      "phase" => "pre_agent_contract_lock",
      "red_on_base_count" => length(rows),
      "acceptance_criteria" => rows
    }
  end

  defp criterion_row(criterion, seeds_by_ac) do
    id = Map.fetch!(criterion, "id")

    %{
      "id" => id,
      "expected_on_base" => "fail",
      "required_test_refs" => criterion["required_test_refs"] || [],
      "seed_ids" =>
        seeds_by_ac
        |> Map.get(id, [])
        |> Enum.map(& &1["seed_id"])
        |> Enum.sort()
    }
  end

  defp stringify_map(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value), do: value
end
