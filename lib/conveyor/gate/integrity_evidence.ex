defmodule Conveyor.Gate.IntegrityEvidence do
  @moduledoc """
  ADR-23 — produce the IntegritySentinel `integrity_verdict` for the loop.

  Thin, deterministic wrapper over `Conveyor.Verification.IntegritySentinel`: run
  the (anti-vacuity) probes over a slice run's observations and return the verdict
  string that `Conveyor.Gate.TrustEvidence` already reads from the run output.

  ## The safety property (why this is safe to wire incrementally)

  A probe with no observation evaluates to `not_assessed` (never `failed`), and the
  overall verdict is `not_assessed` unless some probe actually failed/was suspect.
  `TrustEvidence` maps `not_assessed` to a non-blocking integrity signal, so wiring
  the sentinel with *partial* observations can never force a spurious abstain — it
  only abstains on a genuine probe failure (e.g. production source mutated during
  the test run, a hidden network/secret dependency). As real observation producers
  come online per probe, the gate tightens automatically.

  ## Remaining work (the producers — a dedicated pass)

  This is the tested seam. What is NOT yet wired is the *collection* of probe
  observations in the production loop (hermeticity from the sandbox/toolchain env,
  source-mutation/mount-boundary from the diff, falsifier survival from the
  contract's seeds, etc.) and the write of `output["integrity_verdict"]`. That
  needs care: it must not change the asserted station sequence, and hermeticity
  must only be asserted under a hermetic backend (docker) so local-backend runs
  stay `not_assessed`/non-blocking. Until then this helper has no production
  caller; calling it with `%{}` is a safe no-op verdict.
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
