defmodule Conveyor.ContractCritic.RepairDiff do
  @moduledoc """
  Typed repair comparison with partial pass-output reuse.
  """

  @spec compare!(map()) :: map()
  def compare!(input) do
    case compare(input) do
      {:ok, diff} -> diff
      {:error, findings} -> raise ArgumentError, "repair diff blocked: #{inspect(findings)}"
    end
  end

  @spec compare(map()) :: {:ok, map()} | {:error, [map()]}
  def compare(input) when is_map(input) do
    normalized = stringify_map(input)
    rejected = MapSet.new(string_list(normalized, "rejected_artifact_refs"))
    after_state = Map.fetch!(normalized, "after")
    changed = MapSet.new(Map.get(after_state, "changed_artifact_refs", []))

    if MapSet.subset?(changed, rejected) do
      {:ok, diff(normalized)}
    else
      {:error,
       [
         %{
           rule_key: "repair.scope_expanded",
           severity: :blocking,
           subject_key: changed |> MapSet.difference(rejected) |> Enum.sort() |> Enum.join(","),
           message: "Only rejected-artifact scope may change during repair"
         }
       ]}
    end
  end

  defp diff(input) do
    before = Map.fetch!(input, "before")
    after_state = Map.fetch!(input, "after")

    {reused, invalidated} =
      reuse_plan(Map.get(before, "pass_outputs", %{}), Map.get(after_state, "pass_inputs", %{}))

    diff =
      %{
        "schema_version" => "conveyor.repair_diff@1",
        "before_digest" => Map.fetch!(before, "digest"),
        "after_digest" => Map.fetch!(after_state, "digest"),
        "comparison_type" => Map.fetch!(input, "materiality"),
        "authority_effect" => Map.fetch!(input, "authority_effect"),
        "changed_artifact_refs" => Map.get(after_state, "changed_artifact_refs", []),
        "reused_pass_outputs" => reused,
        "invalidated_passes" => invalidated
      }

    digest = digest(diff)

    diff
    |> Map.put("repair_diff_digest", "sha256:#{digest}")
    |> Map.put("id", "repair_diff:sha256:#{digest}")
  end

  defp reuse_plan(pass_outputs, pass_inputs) do
    pass_outputs
    |> Enum.sort_by(fn {pass, _output} -> pass end)
    |> Enum.reduce({[], []}, fn {pass, output}, {reused, invalidated} ->
      if Map.get(output, "input_refs", []) == Map.get(pass_inputs, pass, []) do
        {reused ++ [Map.fetch!(output, "output_ref")], invalidated}
      else
        {reused, invalidated ++ [pass]}
      end
    end)
  end

  defp string_list(map, key) do
    case Map.get(map, key, []) do
      values when is_list(values) -> values
      _other -> raise ArgumentError, "#{key} must be a list"
    end
  end

  defp digest(value) do
    value
    |> canonical_term()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> stringify_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [key, canonical_term(value)] end)
  end

  defp canonical_term(values) when is_list(values), do: Enum.map(values, &canonical_term/1)
  defp canonical_term(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
