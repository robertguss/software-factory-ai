defmodule Conveyor.Cassettes.Freshness do
  @moduledoc """
  Separates cassette generation and evaluation surfaces.
  """

  @generation_keys [
    :prompt_digest,
    :role_view_digest,
    :context_pack_digest,
    :adapter_profile_digest,
    :tool_contract_digest
  ]

  @evaluation_keys [
    :gate_digest,
    :verification_digest,
    :obligation_digest
  ]

  @spec surface_digests(map()) :: map()
  def surface_digests(surface) when is_map(surface) do
    %{
      generation_freshness_digest: digest(take(surface, @generation_keys)),
      evaluation_surface_digest: digest(take(surface, @evaluation_keys)),
      generation_surface: take(surface, @generation_keys),
      evaluation_surface: take(surface, @evaluation_keys)
    }
  end

  @spec classify(map(), map()) :: :fresh | :hybrid_replay_eligible | :generation_stale
  def classify(recorded, current) do
    cond do
      recorded.generation_freshness_digest != current.generation_freshness_digest ->
        :generation_stale

      recorded.evaluation_surface_digest != current.evaluation_surface_digest ->
        :hybrid_replay_eligible

      true ->
        :fresh
    end
  end

  defp take(surface, keys) do
    Map.new(keys, &{&1, value(surface, &1)})
  end

  defp digest(value) do
    value
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&"sha256:#{&1}")
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  # Recurse into lists too (matches causal_transcript/replay_engine), so a list-of-maps surface
  # value is canonicalized rather than passing through Jason.encode! in insertion order.
  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
