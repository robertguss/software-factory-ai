defmodule Conveyor.Planning.InterfaceGraph do
  @moduledoc """
  Interface contract and binding readiness analysis.

  Interface readiness is represented here, not as Slice work dependencies.
  """

  @spec analyze(map()) :: map()
  def analyze(input) when is_map(input) do
    normalized = normalize_value(input)
    contracts = Map.get(normalized, :contracts, [])
    bindings = Map.get(normalized, :bindings, [])
    contracts_by_key = Map.new(contracts, &{&1.interface_key, &1})

    {readiness, diagnostics} =
      bindings
      |> Enum.filter(&(&1.direction in ["requires", :requires]))
      |> Enum.map_reduce([], fn binding, diagnostics ->
        case Map.fetch(contracts_by_key, binding.interface_key) do
          {:ok, contract} ->
            if version_satisfies?(contract.version, Map.get(binding, :required_version_range)) do
              {readiness(binding, contract), diagnostics}
            else
              {nil, [incompatible_diagnostic(binding) | diagnostics]}
            end

          :error ->
            {nil, [missing_provider_diagnostic(binding) | diagnostics]}
        end
      end)

    diagnostics = Enum.reverse(diagnostics)

    %{
      status: if(diagnostics == [], do: :ready, else: :blocked),
      contracts: contracts,
      bindings: bindings,
      readiness: Enum.reject(readiness, &is_nil/1),
      diagnostics: diagnostics,
      pairwise_work_edges: []
    }
  end

  defp readiness(binding, contract) do
    %{
      interface_key: binding.interface_key,
      provider_slice_key: contract.owner_slice_key,
      consumer_slice_key: binding.slice_key,
      provider_version: contract.version,
      required_version_range: Map.get(binding, :required_version_range),
      status: :ready,
      lock_level: contract.lock_level,
      compatibility_policy: contract.compatibility_policy
    }
  end

  defp missing_provider_diagnostic(binding) do
    %{
      rule_key: "interface_provider_missing",
      severity: :blocking,
      subject_key: "#{binding.slice_key} -> #{binding.interface_key}"
    }
  end

  defp incompatible_diagnostic(binding) do
    %{
      rule_key: "interface_version_incompatible",
      severity: :blocking,
      subject_key: "#{binding.slice_key} -> #{binding.interface_key}"
    }
  end

  defp version_satisfies?(_version, nil), do: true

  defp version_satisfies?(version, range) do
    version_number = parse_version(version)

    range
    |> String.split(" ", trim: true)
    |> Enum.all?(&constraint_satisfied?(version_number, &1))
  end

  defp constraint_satisfied?(version, ">=" <> expected), do: version >= parse_version(expected)
  defp constraint_satisfied?(version, ">" <> expected), do: version > parse_version(expected)
  defp constraint_satisfied?(version, "<=" <> expected), do: version <= parse_version(expected)
  defp constraint_satisfied?(version, "<" <> expected), do: version < parse_version(expected)
  defp constraint_satisfied?(version, expected), do: version == parse_version(expected)

  # Compare all numeric segments, not just the major. Elixir compares lists element-wise,
  # so [2, 0] < [2, 1] and [1, 5] > [1], giving correct multi-segment version verdicts.
  defp parse_version(version) when is_integer(version), do: [version]

  defp parse_version(version) when is_binary(version) do
    version
    |> String.split(".", trim: true)
    |> Enum.map(&String.to_integer/1)
  end

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
