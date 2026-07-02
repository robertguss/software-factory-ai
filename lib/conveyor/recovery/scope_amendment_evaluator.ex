defmodule Conveyor.Recovery.ScopeAmendmentEvaluator do
  @moduledoc """
  nyrl.2 — the deterministic authority for scope amendments: "the agent requests, the policy
  decides." Given the `out_of_scope_path` paths the diff-scope gate rejected, the agent's stated
  rationale, and the policy bounds, it GRANTS (widen the allow-list) or DENIES (park `scope_denied`).

  Pure and side-effect free — this is the trust boundary, so no input the agent controls can move a
  path from protected to allowed. Deny precedence is safety-first:

    1. `:protected_path`   — any offending path is protected (tests/**, locked tests, policy files).
       Protected always beats allowed; no request, rationale, or allowlist can override it.
    2. `:not_on_allowlist` — an offending path is outside the profile's amendment allowlist. An empty
       allowlist therefore fails closed (nothing is eligible for grant).
    3. `:extra_file_cap`   — more offending files than the amendment may add.

  Only when every bound holds is a grant returned, carrying the widened `allowed_path_globs` (the
  caller mints this into a NEW DiffPolicy/ContractLock version — ADR-20, never in-place) plus the
  rationale for the audit trail. The rationale is metadata only; it never affects the decision.
  """

  alias Conveyor.PathGlob

  @type request :: %{
          required(:offending_paths) => [String.t()],
          required(:allowed_path_globs) => [String.t()],
          required(:protected_path_globs) => [String.t()],
          required(:allowlist_globs) => [String.t()],
          required(:max_extra_files) => non_neg_integer(),
          optional(:rationale) => String.t() | nil
        }

  @type grant :: %{added_globs: [String.t()], allowed_path_globs: [String.t()], rationale: term()}
  @type denial :: %{
          park_reason: :scope_denied,
          violated_bound: :protected_path | :not_on_allowlist | :extra_file_cap,
          offending: [String.t()],
          detail: String.t()
        }

  @spec evaluate(request()) :: {:grant, grant()} | {:deny, denial()}
  def evaluate(request) do
    offending = request.offending_paths
    rationale = Map.get(request, :rationale)

    with :ok <- check_protected(offending, request.protected_path_globs),
         :ok <- check_allowlist(offending, request.allowlist_globs),
         :ok <- check_cap(offending, request.max_extra_files) do
      {:grant,
       %{
         added_globs: offending,
         allowed_path_globs: widen(request.allowed_path_globs, offending),
         rationale: rationale
       }}
    end
  end

  # Protected beats everything — checked first, and no allowlist/cap can rescue a protected path.
  defp check_protected(offending, protected_globs) do
    case Enum.filter(offending, &PathGlob.match_any?(&1, protected_globs)) do
      [] -> :ok
      hits -> {:deny, denial(:protected_path, hits, "protected path(s) can never be granted")}
    end
  end

  defp check_allowlist(offending, allowlist_globs) do
    case Enum.reject(offending, &PathGlob.match_any?(&1, allowlist_globs)) do
      [] -> :ok
      hits -> {:deny, denial(:not_on_allowlist, hits, "path(s) outside the amendment allowlist")}
    end
  end

  defp check_cap(offending, max_extra_files) do
    count = length(offending)

    if count <= max_extra_files do
      :ok
    else
      {:deny,
       denial(:extra_file_cap, offending, "#{count} extra files exceeds cap #{max_extra_files}")}
    end
  end

  defp denial(bound, offending, detail) do
    %{park_reason: :scope_denied, violated_bound: bound, offending: offending, detail: detail}
  end

  # New allow-globs are appended (order-stable, deduped) — the widened scope the caller versions.
  defp widen(allowed, offending), do: allowed ++ Enum.reject(offending, &(&1 in allowed))
end
