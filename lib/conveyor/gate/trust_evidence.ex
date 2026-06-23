defmodule Conveyor.Gate.TrustEvidence do
  @moduledoc """
  ADR-23 / M4-A1 — assemble the `Conveyor.Gate.TrustScore` evidence map from the
  trust signals a slice run produces, under a **fail-closed taxonomy**.

  Threads the loop's real signals — acceptance calibration and baseline health,
  written into the slice run output by their stations
  (`"test_pack_calibration"` / `"baseline_health_status"`) — into the evidence the
  gate `Finalizer` scores.

  ## Fail-closed, not fail-open (M4-A1)

  An *always-assessable* signal that is **expected but absent** routes to its
  abstaining token (`calibration -> :not_assessed`, `baseline -> :unknown`), NOT to
  its passing token. A run that never produced a calibration/baseline signal
  therefore **abstains** (parks for human review) instead of silently
  auto-accepting. This inverts the original "safe by construction" rollout, which
  laundered every unmeasured signal to its passing value — making the calibrated
  abstain band structurally unreachable on the live path.

  A signal is treated as *non-blocking* only when a producer **declares** it
  not-assessable on this backend — listed in the output key `"trust_not_assessable"`
  (e.g. hermeticity under the `:local` backend). A declared-N/A signal routes to the
  neutral middle token, never to a passing one.

  ## Staged ownership (M4)

  - **calibration + baseline** — fail-closed here (M4-A1).
  - **integrity** — *un-laundered (M4)*: the real IntegritySentinel verdict passes
    through. The verify station requires only the backend-agnostic `source_mutation`
    probe on `:local` (hermeticity is docker-only), so a clean run is genuinely
    `"trustworthy"` and a real production-source mutation is `"untrustworthy"` ->
    abstain/park. An absent verdict fails closed to `"not_assessed"`.
  - **replay + corpus** — owned by stream B (real replay-divergence producer +
    corpus boost). A1 leaves their laundering in place; it only adds the
    declared-not-assessable override path.
  """

  alias Conveyor.Gate.TrustScore

  # Signal names a producer may declare not-assessable via the output key
  # "trust_not_assessable". A declared-but-absent signal routes to its neutral
  # middle token instead of its abstaining token.
  @assessable_signals [:calibration, :baseline, :integrity, :replay, :corpus]

  @doc "Build TrustScore evidence from a slice run's accumulated `output` map."
  @spec from_run_output(map()) :: TrustScore.evidence()
  def from_run_output(output) when is_map(output) do
    assemble(%{
      calibration: get_in(output, ["test_pack_calibration", "status"]),
      baseline: Map.get(output, "baseline_health_status"),
      integrity: Map.get(output, "integrity_verdict"),
      replay: Map.get(output, "replay_divergence"),
      corpus_pass_rate: Map.get(output, "corpus_pass_rate"),
      declared_not_assessable: not_assessable_set(output)
    })
  end

  @doc """
  Normalize a raw signals map into TrustScore evidence.

  Expected-but-absent always-assessable signals fail closed (`:not_assessed` /
  `:unknown`). A signal named in `:declared_not_assessable` routes to its neutral
  middle token instead (non-blocking).
  """
  @spec assemble(map()) :: TrustScore.evidence()
  def assemble(signals) when is_map(signals) do
    na = signals |> Map.get(:declared_not_assessable, []) |> normalize_na_set()

    %{
      integrity_verdict: integrity(Map.get(signals, :integrity)),
      calibration_status:
        assess(:calibration, na, calibration(Map.get(signals, :calibration)), :not_assessed),
      baseline_status: assess(:baseline, na, baseline(Map.get(signals, :baseline)), :unknown),
      replay_divergence: assess(:replay, na, replay(Map.get(signals, :replay)), :unknown),
      corpus_pass_rate: corpus(Map.get(signals, :corpus_pass_rate))
    }
  end

  # A producer-declared not-assessable signal resolves to its neutral middle token.
  defp assess(signal, na_set, measured, middle_token) do
    if signal in na_set, do: middle_token, else: measured
  end

  # --- M4-A1: calibration + baseline fail closed -----------------------------

  defp calibration(status) when status in [:valid, "valid"], do: :valid
  defp calibration(status) when status in [:invalid, "invalid"], do: :invalid
  defp calibration(status) when status in [:not_assessed, "not_assessed"], do: :not_assessed
  # Expected-but-absent: fail closed (was the silent `:valid` leak).
  defp calibration(_absent), do: :not_assessed

  defp baseline(status) when status in [:passed, "passed", :green, "green"], do: :green
  defp baseline(status) when status in [:failed, "failed", :red, "red"], do: :red

  defp baseline(status) when status in [:not_assessed, "not_assessed", :unknown, "unknown"],
    do: :unknown

  # Expected-but-absent: fail closed (was the silent `:green` leak).
  defp baseline(_absent), do: :unknown

  # --- still laundered (owned downstream); see moduledoc F13 flag ------------

  # M4 (integrity un-laundered): pass the real IntegritySentinel verdict through instead of
  # laundering every value to "trustworthy". The verify station now requires only the
  # backend-agnostic source_mutation probe on :local (hermeticity is docker-only), so a clean
  # run is genuinely "trustworthy" and a real production-source mutation is "untrustworthy" ->
  # the trust score abstains -> the slice parks for human + AI investigation. An absent verdict
  # fails closed to "not_assessed" (investigate); the verify station always supplies one on the
  # live path, so the reference stays "trustworthy" (now earned, not fabricated).
  defp integrity(verdict) when verdict in [:trustworthy, "trustworthy"], do: "trustworthy"
  defp integrity(verdict) when verdict in [:suspect, "suspect"], do: "suspect"
  defp integrity(verdict) when verdict in [:untrustworthy, "untrustworthy"], do: "untrustworthy"
  defp integrity(verdict) when verdict in [:not_assessed, "not_assessed"], do: "not_assessed"
  defp integrity(_absent), do: "not_assessed"

  defp replay(divergence) when divergence in [:diverged, "diverged"], do: :diverged
  defp replay(_divergence), do: :none

  defp corpus(rate) when is_float(rate), do: rate
  defp corpus(_rate), do: nil

  # --- declared-not-assessable set --------------------------------------------

  defp not_assessable_set(output) do
    output |> Map.get("trust_not_assessable", []) |> List.wrap()
  end

  defp normalize_na_set(list) when is_list(list) do
    list |> Enum.map(&normalize_signal_name/1) |> Enum.reject(&is_nil/1)
  end

  defp normalize_na_set(_other), do: []

  defp normalize_signal_name(name) when name in @assessable_signals, do: name
  defp normalize_signal_name("calibration"), do: :calibration
  defp normalize_signal_name("baseline"), do: :baseline
  defp normalize_signal_name("integrity"), do: :integrity
  defp normalize_signal_name("replay"), do: :replay
  defp normalize_signal_name("corpus"), do: :corpus
  defp normalize_signal_name(_other), do: nil
end
