defmodule Conveyor.Gate.ParkReason do
  @moduledoc """
  Typed park-reason taxonomy (a3hf.1.3.1).

  Folds the producers' raw park causes into a typed, extensible enum so the needs-a-human inbox can
  triage parked slices by *why* they parked rather than parsing free text:

    * `:weak_acceptance_tests` — the locked acceptance suite already passed at the base commit, so it
      does not distinguish the new behavior (TrustScore calibration `:invalid`).
    * `:no_behavior_change` — the attempt changed nothing (the convergence sentinel's `no_progress`).
    * `:missing_signal` — a required trust signal was not assessed (integrity/calibration/baseline/
      replay unknown), so the gate could not calibrate confidence.
    * `:unclassified` — the safe default: a park cause the taxonomy does not yet name. Every fall to
      the default is logged so new reasons surface and can be promoted to a named value.

  Producers hand this module their native shape (`from_gate_evidence/1` for the gate's TrustScore
  abstain evidence, `from_signal/1` for the sentinel's typed reason strings). Unknown input never
  raises — it maps to `:unclassified` and logs.
  """

  require Logger

  # :scope_denied is a policy-deny park (nyrl.2), set explicitly by the scope-amendment path — NOT
  # derived from trust evidence, so it has no `from_gate_evidence`/`from_signal` clause.
  @named [:weak_acceptance_tests, :no_behavior_change, :missing_signal, :scope_denied]
  @default :unclassified

  @type t ::
          :weak_acceptance_tests
          | :no_behavior_change
          | :missing_signal
          | :scope_denied
          | :unclassified

  @spec values() :: [t()]
  def values, do: @named ++ [@default]

  @spec default() :: t()
  def default, do: @default

  @doc "Classify a gate TrustScore `:abstain` from its recorded evidence map."
  @spec from_gate_evidence(map() | term()) :: t()
  def from_gate_evidence(evidence) when is_map(evidence) do
    cond do
      calibration_invalid?(evidence) -> :weak_acceptance_tests
      missing_signal?(evidence) -> :missing_signal
      true -> unclassified({:gate_evidence, evidence})
    end
  end

  def from_gate_evidence(other), do: unclassified({:gate_evidence, other})

  @doc "Fold a producer's typed park-reason string (e.g. the convergence sentinel) into the taxonomy."
  @spec from_signal(String.t() | term()) :: t()
  def from_signal("no_progress"), do: :no_behavior_change
  def from_signal(other), do: unclassified({:signal, other})

  defp calibration_invalid?(evidence),
    do: fetch(evidence, :calibration_status) in [:invalid, "invalid"]

  defp missing_signal?(evidence) do
    fetch(evidence, :integrity_verdict) in [nil, "not_assessed"] or
      fetch(evidence, :calibration_status) in [:not_assessed, "not_assessed"] or
      fetch(evidence, :baseline_status) in [nil, :unknown, "unknown"] or
      fetch(evidence, :replay_divergence) in [
        nil,
        :unknown,
        "unknown",
        :baseline_absent,
        "baseline_absent"
      ]
  end

  defp unclassified(cause) do
    Logger.warning("park_reason taxonomy: unclassified cause #{inspect(cause)} -> :#{@default}")
    @default
  end

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key))
    end
  end
end
