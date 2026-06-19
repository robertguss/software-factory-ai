defmodule Conveyor.Planning.Claims do
  @moduledoc """
  Compiles deterministic source anchors into a ClaimSet.
  """

  @spec compile(map(), [map()]) :: map()
  def compile(subject, anchors) when is_map(subject) and is_list(anchors) do
    anchor_by_pointer =
      Map.new(anchors, fn anchor ->
        pointer = value(anchor, :pointer)

        {pointer,
         %{
           origin: value(anchor, :origin),
           source_anchor_refs: List.wrap(value(anchor, :source_anchor_ref))
         }}
      end)

    claims_by_pointer =
      subject
      |> leaf_pointers()
      |> Map.new(fn pointer ->
        deterministic = Map.get(anchor_by_pointer, pointer)

        claim =
          deterministic ||
            %{
              origin: :agent_inferred,
              source_anchor_refs: []
            }

        {pointer, claim}
      end)

    %{
      subject_content_digest: digest(subject),
      claims_by_pointer: claims_by_pointer,
      claim_set_digest: digest(claims_by_pointer)
    }
  end

  defp leaf_pointers(value, path \\ [])

  defp leaf_pointers(%{} = map, path) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.flat_map(fn {key, nested} ->
      leaf_pointers(nested, path ++ [escape_pointer(to_string(key))])
    end)
  end

  defp leaf_pointers(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      leaf_pointers(value, path ++ [Integer.to_string(index)])
    end)
  end

  defp leaf_pointers(_value, path), do: ["/" <> Enum.join(path, "/")]

  defp escape_pointer(part) do
    part
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end

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

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
