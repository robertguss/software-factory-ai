defmodule Conveyor.Gate.IntegrityEvidence do
  @moduledoc """
  ADR-23 — produce the IntegritySentinel `integrity_verdict` for the loop.

  Thin, deterministic wrapper over `Conveyor.Verification.IntegritySentinel`: run
  the (anti-vacuity) probes over a slice run's observations and return the verdict
  string that `Conveyor.Gate.TrustEvidence` already reads from the run output.

  ## The verdict (M4: un-laundered)

  A probe with no observation evaluates to `not_assessed` (never `failed`), and the
  overall verdict is `not_assessed` unless some probe actually failed/was suspect.
  `TrustEvidence` now passes the real verdict through (M4 un-laundering): a genuine
  probe failure (production source mutated, a hidden network/secret dependency) is
  `"untrustworthy"`, and `not_assessed` (no assessable probe) **fails closed** — both
  abstain/park for investigation. The verify station requires only the backend-agnostic
  `source_mutation` probe on `:local` (hermeticity is docker-only), so a clean local
  run is genuinely `"trustworthy"` rather than vacuously non-blocking.

  ## Remaining work (the producers — a dedicated pass)

  `Conveyor.Stations.Verify` wires this helper in the production loop (`verify.ex`),
  supplying the `source_mutation` (always) + `hermeticity` (docker) observations. What
  is NOT yet wired is the *collection* of the remaining probe observations
  (mount-boundary from the diff, falsifier survival from the contract's seeds, etc.),
  which a later C-stream pass adds (each as an additional required probe). Calling this
  helper with `%{}` yields a `not_assessed` verdict (now fail-closed).
  """

  alias Conveyor.Verification.IntegritySentinel

  @doc """
  Compute the integrity verdict (`"trustworthy" | "suspect" | "not_assessed" |
  "untrustworthy"`) from a map of probe observations. `opts` may carry the spec
  identity (`:test_pack_id`, `:integrity_spec_digest`, `:sample_no`, `:slice_id`,
  `:run_spec_id`), `:required_probes`, and `:evaluated_at` (the verdict does not
  depend on the timestamp; a fixed default keeps it deterministic).
  """
  @spec verdict(map(), keyword()) :: String.t()
  def verdict(observations, opts \\ []) when is_map(observations) and is_list(opts) do
    spec = %{
      test_pack_id: Keyword.get(opts, :test_pack_id, "unknown"),
      integrity_spec_digest: Keyword.get(opts, :integrity_spec_digest, "unknown"),
      sample_no: Keyword.get(opts, :sample_no, 1),
      slice_id: Keyword.get(opts, :slice_id, "unknown"),
      run_spec_id: Keyword.get(opts, :run_spec_id)
    }

    run_opts =
      [evaluated_at: Keyword.get(opts, :evaluated_at, "1970-01-01T00:00:00Z")]
      |> maybe_put(:required_probes, Keyword.get(opts, :required_probes))

    spec
    |> IntegritySentinel.run(observations, run_opts)
    |> Map.fetch!("verdict")
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
