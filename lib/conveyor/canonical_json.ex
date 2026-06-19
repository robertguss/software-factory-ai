defmodule Conveyor.CanonicalJson do
  @moduledoc """
  Deterministic, cross-runtime canonical JSON encoding for content-addressed digests.

  Object keys are sorted recursively; `nil`/`true`/`false` encode as JSON literals; other
  atoms encode as their string form. This follows the `rfc8785-jcs` canonicalization profile
  (ADR-04) closely enough for stable evidence digests and, unlike `:erlang.term_to_binary/1`,
  is reproducible across OTP/ERTS versions.
  """

  @doc "Canonical JSON string for `term` (object keys sorted, applied recursively)."
  @spec encode(term()) :: binary()
  def encode(%{} = map) do
    inner =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map_join(",", fn {key, value} ->
        Jason.encode!(to_string(key)) <> ":" <> encode(value)
      end)

    "{" <> inner <> "}"
  end

  def encode(list) when is_list(list), do: "[" <> Enum.map_join(list, ",", &encode/1) <> "]"
  def encode(value) when value in [nil, true, false], do: Jason.encode!(value)
  def encode(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  def encode(value), do: Jason.encode!(value)

  @doc """
  `sha256:`-prefixed lowercase hex digest of the canonical JSON encoding of `term`.
  """
  @spec digest(term()) :: binary()
  def digest(term) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, encode(term)), case: :lower)
  end
end
