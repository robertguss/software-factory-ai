defmodule Conveyor.Gate.TrustEvidence do
  @moduledoc """
  ADR-23 — assemble the `Conveyor.Gate.TrustScore` evidence map from the trust
  signals a slice run already produces.

  Threads the loop's real, already-computed signals — acceptance calibration and
  baseline health, written into the slice run output by their stations
  (`"test_pack_calibration"` / `"baseline_health_status"`) — into the evidence the
  gate `Finalizer` scores.

  ## Staged rollout (safe by construction)

  Signals not yet wired into the production loop (the IntegritySentinel verdict,
  replay divergence, corpus pass rate) default to **non-blocking**. Threading can
  therefore never force a spurious abstain: a passed gate abstains only on a
  *recognized negative* signal (`calibration_status: :invalid` or
  `baseline_status: :red`). As more signals are wired in, they tighten the gate —
  earned autonomy rather than a day-one cliff that parks everything.
  """

  alias Conveyor.Gate.TrustScore

  @doc "Build TrustScore evidence from a slice run's accumulated `output` map."
  @spec from_run_output(map()) :: TrustScore.evidence()
  def from_run_output(output) when is_map(output) do
    assemble(%{
      calibration: get_in(output, ["test_pack_calibration", "status"]),
      baseline: Map.get(output, "baseline_health_status"),
      integrity: Map.get(output, "integrity_verdict"),
      replay: Map.get(output, "replay_divergence"),
      corpus_pass_rate: Map.get(output, "corpus_pass_rate")
    })
  end

  @doc "Normalize a raw signals map into TrustScore evidence (unmeasured -> non-blocking)."
  @spec assemble(map()) :: TrustScore.evidence()
  def assemble(signals) when is_map(signals) do
    %{
      integrity_verdict: integrity(Map.get(signals, :integrity)),
      calibration_status: calibration(Map.get(signals, :calibration)),
      baseline_status: baseline(Map.get(signals, :baseline)),
      replay_divergence: replay(Map.get(signals, :replay)),
      corpus_pass_rate: corpus(Map.get(signals, :corpus_pass_rate))
    }
  end

  # Only an explicit negative blocks; unmeasured / unrecognized is non-blocking.
  defp calibration(status) when status in [:invalid, "invalid"], do: :invalid
  defp calibration(_status), do: :valid

  defp baseline(status) when status in [:failed, "failed", :red, "red"], do: :red
  defp baseline(_status), do: :green

  defp integrity(verdict) when verdict in [:suspect, "suspect"], do: "suspect"
  defp integrity(verdict) when verdict in [:untrustworthy, "untrustworthy"], do: "untrustworthy"
  defp integrity(_verdict), do: "trustworthy"

  defp replay(divergence) when divergence in [:diverged, "diverged"], do: :diverged
  defp replay(_divergence), do: :none

  defp corpus(rate) when is_float(rate), do: rate
  defp corpus(_rate), do: nil
end
