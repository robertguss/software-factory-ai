defmodule Conveyor.Planning.SelectiveRecompilation do
  @moduledoc """
  Plans affected-pass recompilation from invalidation inputs.

  Reuse is intentionally conservative: an output can be retained only when every
  input ref is explicitly proven valid, no input/output is invalidated, and any
  attached approval is still valid.
  """

  @low_confidence_threshold 0.8

  @spec plan(map()) :: map()
  def plan(input) when is_map(input) do
    passes = list(input, :passes)

    if low_confidence?(value(input, :impact_confidence)) do
      %{
        "status" => "low_confidence_fail_wide",
        "fail_wide" => true,
        "rerun_passes" => pass_keys(passes),
        "retained_outputs" => [],
        "blocking_reasons" => ["impact_confidence_low"]
      }
    else
      invalidated_refs = input |> strings(:invalidated_refs) |> MapSet.new()
      proven_valid_refs = input |> strings(:proven_valid_refs) |> MapSet.new()
      valid_approval_refs = input |> strings(:valid_approval_refs) |> MapSet.new()

      rerun_passes =
        passes
        |> Enum.filter(&rerun?(&1, invalidated_refs))
        |> pass_keys()

      %{
        "status" => "selective",
        "fail_wide" => false,
        "rerun_passes" => rerun_passes,
        "retained_outputs" =>
          retained_outputs(passes, invalidated_refs, proven_valid_refs, valid_approval_refs),
        "blocking_reasons" => []
      }
    end
  end

  defp rerun?(pass, invalidated_refs) do
    output_invalidated? = value(pass, :output_ref) in invalidated_refs

    input_invalidated? =
      Enum.any?(strings(pass, :input_refs), &MapSet.member?(invalidated_refs, &1))

    output_invalidated? or input_invalidated?
  end

  defp retained_outputs(passes, invalidated_refs, proven_valid_refs, valid_approval_refs) do
    passes
    |> Enum.reject(&rerun?(&1, invalidated_refs))
    |> Enum.filter(&retainable?(&1, proven_valid_refs, valid_approval_refs))
    |> Enum.map(&retained_output/1)
    |> Enum.sort_by(& &1["pass_key"])
  end

  defp retainable?(pass, proven_valid_refs, valid_approval_refs) do
    inputs_proven? =
      pass
      |> strings(:input_refs)
      |> Enum.all?(&MapSet.member?(proven_valid_refs, &1))

    approval_valid? =
      case value(pass, :approval_ref) do
        nil -> true
        approval_ref -> MapSet.member?(valid_approval_refs, approval_ref)
      end

    inputs_proven? and approval_valid? and present?(value(pass, :output_digest))
  end

  defp retained_output(pass) do
    %{
      "pass_key" => value(pass, :pass_key),
      "output_ref" => value(pass, :output_ref),
      "output_digest" => value(pass, :output_digest)
    }
    |> put_optional("approval_ref", value(pass, :approval_ref))
  end

  defp pass_keys(passes) do
    passes
    |> Enum.map(&value(&1, :pass_key))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp low_confidence?(confidence) when is_number(confidence),
    do: confidence < @low_confidence_threshold

  defp low_confidence?(_confidence), do: true

  defp strings(map, key) do
    map
    |> value(key, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp present?(value), do: value not in [nil, "", []]
end
