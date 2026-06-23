defmodule Conveyor.Test.TrustDiscrimination do
  @moduledoc """
  M4-A7 — the reusable discrimination-harness pattern for the trust gate.

  A gate that only ever *passes when green* proves nothing; the load-bearing
  property is that it *abstains/fails when a signal is broken or missing*. This
  helper makes that property cheap to assert from every sub-stream's tests:

    * `assert_discriminates/1` — a fully-green reference auto-accepts, and the same
      reference with ONE signal overridden to a bad token abstains.
    * `band_of_output/1` — drive a raw slice `output` map through the REAL assembly
      path (`TrustEvidence.from_run_output/1 -> TrustScore.evaluate/1`) and return
      the band. The anti-vacuity linchpin: a "missing signal -> abstain" test MUST
      go through this (not a hand-built evidence map), or it proves nothing about
      the laundering being gone (see the cautionary vacuous case in
      `trust_score_test.exs`).

  Determinism: pure fusion over recorded evidence, no I/O.
  """

  import ExUnit.Assertions

  alias Conveyor.Gate.TrustEvidence
  alias Conveyor.Gate.TrustScore

  # The known-good reference evidence: every signal measured-good. corpus 0.95
  # (a real boost) so the reference clears the band with margin (0.9925).
  @reference %{
    integrity_verdict: "trustworthy",
    calibration_status: :valid,
    baseline_status: :green,
    replay_divergence: :none,
    corpus_pass_rate: 0.95
  }

  @doc "The known-good reference evidence map (every signal measured-good)."
  @spec reference() :: TrustScore.evidence()
  def reference, do: @reference

  @doc """
  Assert the gate discriminates: the green reference auto-accepts, and the
  reference with `broken_override` merged in abstains.
  """
  @spec assert_discriminates(map()) :: :ok
  def assert_discriminates(broken_override) when is_map(broken_override) do
    assert TrustScore.evaluate(reference()).band == :auto_accept,
           "reference evidence must auto-accept"

    broken = Map.merge(reference(), broken_override)

    assert TrustScore.evaluate(broken).band == :abstain,
           "evidence with #{inspect(broken_override)} must abstain, got auto_accept"

    :ok
  end

  @doc """
  Band reached by driving a raw slice `output` map through the real assembly path.

  Use this (not a hand-built evidence map) to prove a *missing* signal abstains —
  it exercises `TrustEvidence`, where the laundering lived.
  """
  @spec band_of_output(map()) :: TrustScore.band()
  def band_of_output(output) when is_map(output) do
    output
    |> TrustEvidence.from_run_output()
    |> TrustScore.evaluate()
    |> Map.fetch!(:band)
  end
end
