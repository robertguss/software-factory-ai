defmodule Conveyor.Planning.CodeImpactOverlay do
  @moduledoc """
  Advisory code impact overlay for planning context.

  This is deliberately not a dependency edge. It summarizes likely affected
  implementation surfaces and confidence for context assembly.
  """

  defstruct [:status, :confidence, :hard_dependency?, :authority_effect, :impact]

  @impact_keys [:modules, :symbols, :interfaces, :tests, :migrations]

  @spec build(map()) :: %__MODULE__{}
  def build(attrs) when is_map(attrs) do
    %__MODULE__{
      status: :advisory,
      confidence: value(attrs, :confidence) || 0.0,
      hard_dependency?: false,
      authority_effect: :none,
      impact: Map.new(@impact_keys, &{&1, string_list(attrs, &1)})
    }
  end

  defp string_list(map, key) do
    case value(map, key) do
      values when is_list(values) -> values |> Enum.filter(&is_binary/1) |> Enum.sort()
      _ -> []
    end
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
