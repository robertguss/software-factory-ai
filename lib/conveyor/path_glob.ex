defmodule Conveyor.PathGlob do
  @moduledoc """
  Minimal path-glob matching shared by scope/policy checks: `*` matches within a path segment,
  `**` matches across segments. This is the same semantics the gate stages compute inline
  (diff_scope/policy_compliance/contract_lock/observed_risk each carry a private copy).

  ponytail: extracted for new callers (the scope-amendment evaluator). The 5 existing inline
  copies are left untouched to avoid churning working gate stages; migrating them is a separate
  chore (see the dedup bead filed with nyrl.2).
  """

  @doc "Does `path` match the single glob?"
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(path, glob) do
    glob
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("^#{&1}$"))
    |> Regex.match?(path)
  end

  @doc "Does `path` match any glob in the list? Empty list never matches."
  @spec match_any?(String.t(), [String.t()]) :: boolean()
  def match_any?(_path, []), do: false
  def match_any?(path, globs), do: Enum.any?(globs, &matches?(path, &1))
end
