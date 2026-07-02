defmodule Conveyor.Planning.ScopeCap do
  @moduledoc """
  Per-slice diff-scope cap derivation (nyrl.3). `max_files_changed` is derived from the
  slice's own declared scope — `|declared files| + always-allowed-class headroom + margin`
  — never a flat global constant. A cap derived from the contract means something: "you
  changed more than you declared," which is the real smell; a flat cap punishes
  correctly-sized slices and misses bloated ones.

  Values are config-driven (`config :conveyor, Conveyor.Planning.ScopeCap`) so they live in
  one place, not hardcoded at the call site; per-project-profile overrides land with the
  diff-scope profile surface (nyrl.1.1).
  """

  @defaults [always_allowed_headroom: 3, scope_margin: 1, max_declared_files: 12]

  @doc "Derived per-slice `max_files_changed` for a slice declaring `declared_count` files."
  @spec max_files_changed(non_neg_integer()) :: pos_integer()
  def max_files_changed(declared_count) when is_integer(declared_count) and declared_count >= 0 do
    declared_count + get(:always_allowed_headroom) + get(:scope_margin)
  end

  @doc "The largest declared scope a single slice should carry before it reads as authored-bloated."
  @spec max_declared_files() :: pos_integer()
  def max_declared_files, do: get(:max_declared_files)

  @doc "True when a slice's declared scope exceeds the profile bound (an authoring smell)."
  @spec over_declared_bound?(non_neg_integer()) :: boolean()
  def over_declared_bound?(declared_count), do: declared_count > max_declared_files()

  defp get(key) do
    :conveyor
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, Keyword.fetch!(@defaults, key))
  end
end
