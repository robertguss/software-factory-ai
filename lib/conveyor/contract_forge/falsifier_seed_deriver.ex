defmodule Conveyor.ContractForge.FalsifierSeedDeriver do
  @moduledoc """
  Derives compiler-owned falsifier seeds from upgraded AgentBrief contracts.
  """

  @seed_fields [
    {"falsifying_conditions", "table_negative_row"},
    {"boundary_examples", "boundary_transform"},
    {"forbidden_predicates", "forbidden_predicate"},
    {"property_counterexamples", "property_counterexample"},
    {"metamorphic_relations", "metamorphic_relation"},
    {"interface_incompatibility_cases", "interface_incompatibility"}
  ]

  @spec derive!(map()) :: [map()]
  def derive!(contract) when is_map(contract) do
    contract
    |> stringify_map()
    |> Map.get("acceptance_criteria", [])
    |> Enum.flat_map(&seeds_for_ac/1)
  end

  @spec verify_preserved([map()], [map()]) :: :ok | {:error, [map()]}
  def verify_preserved(original, translated) do
    translated_ids = translated |> Enum.map(&value(&1, :seed_id)) |> MapSet.new()

    findings =
      original
      |> Enum.reject(&(value(&1, :seed_id) in translated_ids))
      |> Enum.map(fn seed ->
        %{
          rule_key: "falsifier_seed_dropped",
          severity: :blocking,
          subject_key: value(seed, :seed_id),
          message: "compiler-derived falsifier seed was not preserved or explicitly superseded"
        }
      end)

    if findings == [], do: :ok, else: {:error, findings}
  end

  defp seeds_for_ac(ac) do
    ac_id = Map.fetch!(ac, "id")

    @seed_fields
    |> Enum.flat_map(fn {field, family} ->
      ac
      |> Map.get(field, [])
      |> Enum.with_index()
      |> Enum.map(fn {payload, index} ->
        %{
          "seed_id" => "falsifier:#{ac_id}:#{family}:#{index}",
          "family" => family,
          "source_acceptance_criterion_id" => ac_id,
          "payload" => payload,
          "preservation_required" => true
        }
      end)
    end)
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value), do: value

  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
