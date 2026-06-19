defmodule Conveyor.Planning.PromptDryCompile do
  @moduledoc """
  Placeholder prompt-structure dry compiler.

  This validates that compiler output can satisfy prompt references without
  launching an implementer or calling a provider.
  """

  @required_fields [
    :acceptance_refs,
    :desired_behavior,
    :key_interfaces,
    :verification_obligation_refs
  ]

  @spec run(map()) :: map()
  def run(input) when is_map(input) do
    normalized = normalize_value(input)
    fields = Map.get(normalized, :contract_fields, %{})
    missing = Enum.filter(@required_fields, &(not present?(Map.get(fields, &1))))

    if missing == [] do
      %{
        status: :passed,
        implementer_launched?: false,
        provider_called?: false,
        prompt_structure: %{
          template_version: "placeholder-contract-prompt@1",
          slice_key: Map.fetch!(normalized, :slice_key),
          required_refs:
            Map.fetch!(fields, :acceptance_refs) ++
              Map.fetch!(fields, :key_interfaces) ++ Map.fetch!(fields, :verification_obligation_refs)
        },
        critical_context_status:
          if(present?(Map.get(normalized, :critical_context_refs)), do: :complete, else: :missing)
      }
    else
      %{
        status: :blocked,
        implementer_launched?: false,
        provider_called?: false,
        missing_fields: missing
      }
    end
  end

  defp present?(value), do: value not in [nil, "", []]

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
