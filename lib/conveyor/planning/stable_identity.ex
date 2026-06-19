defmodule Conveyor.Planning.StableIdentity do
  @moduledoc """
  Deterministic stable-key reconciliation for decomposition candidates.

  Model proposals may suggest structure, but final Slice identity is assigned by
  this compiler pass. Reordering input slices does not affect keys because each
  key is derived from semantic identity, not list position.
  """

  @identity_fields [
    :proposal_key,
    :archetype_key,
    :change_class,
    :requirement_refs,
    :source_anchor_refs,
    :constraint_refs
  ]

  @spec reconcile(map(), keyword()) :: map()
  def reconcile(candidate, opts \\ []) when is_map(candidate) do
    previous_by_proposal =
      opts
      |> Keyword.get(:previous_slices, [])
      |> Enum.map(&normalize_slice/1)
      |> Map.new(&{&1.proposal_key, &1})

    {slices, lineage} =
      candidate
      |> value(:slices)
      |> Enum.map(&normalize_slice/1)
      |> Enum.map_reduce([], &reconcile_slice(&1, previous_by_proposal, &2))

    %{
      candidate: candidate |> normalize_candidate() |> Map.put(:slices, slices),
      lineage: Enum.reverse(lineage)
    }
  end

  defp reconcile_slice(slice, previous_by_proposal, lineage) do
    semantic_digest = semantic_digest(slice)
    previous = Map.get(previous_by_proposal, slice.proposal_key)

    cond do
      previous && previous.semantic_identity_digest == semantic_digest ->
        {
          slice
          |> Map.put(:stable_key, previous.stable_key)
          |> Map.put(:semantic_identity_digest, semantic_digest)
          |> Map.put(:identity_actor, :compiler)
          |> Map.delete(:supersedes_slice_key),
          lineage
        }

      previous ->
        stable_key = stable_key(semantic_digest)

        {
          slice
          |> Map.put(:stable_key, stable_key)
          |> Map.put(:semantic_identity_digest, semantic_digest)
          |> Map.put(:identity_actor, :compiler)
          |> Map.put(:supersedes_slice_key, previous.stable_key),
          [
            %{
              from: previous.stable_key,
              to: stable_key,
              proposal_key: slice.proposal_key,
              reason: "semantic_identity_changed"
            }
            | lineage
          ]
        }

      true ->
        {
          slice
          |> Map.put(:stable_key, stable_key(semantic_digest))
          |> Map.put(:semantic_identity_digest, semantic_digest)
          |> Map.put(:identity_actor, :compiler)
          |> Map.delete(:supersedes_slice_key),
          lineage
        }
    end
  end

  defp normalize_candidate(candidate) do
    candidate
    |> normalize_value()
    |> Map.delete(:stable_key)
    |> Map.delete(:agent_minted_final_id)
  end

  defp normalize_slice(slice) do
    slice
    |> normalize_value()
    |> Map.delete(:stable_key)
    |> Map.delete(:agent_minted_final_id)
    |> then(fn normalized ->
      normalized
      |> Map.put(:proposal_key, value(normalized, :proposal_key))
      |> Map.put(
        :semantic_identity_digest,
        value(normalized, :semantic_identity_digest) || semantic_digest(normalized)
      )
      |> maybe_restore_stable_key(slice)
    end)
  end

  defp maybe_restore_stable_key(normalized, original) do
    case value(original, :stable_key) do
      nil -> normalized
      stable_key -> Map.put(normalized, :stable_key, stable_key)
    end
  end

  defp semantic_digest(slice) do
    slice
    |> Map.take(@identity_fields)
    |> digest()
  end

  defp stable_key("sha256:" <> digest), do: "SLC-" <> String.upcase(String.slice(digest, 0, 12))

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, nested} ->
      {key |> to_string() |> String.to_atom(), normalize_value(nested)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value

  defp digest(value) do
    "sha256:" <>
      (value
       |> canonical_json()
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end

  defp canonical_json(%{} = map) do
    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(values) when is_list(values),
    do: "[" <> Enum.map_join(values, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
