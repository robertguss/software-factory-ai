defmodule Conveyor.Gate.TrustScore do
  @moduledoc """
  ADR-23 — calibrated trust scoring for the ternary gate verdict.

  A **pure** fusion of signals Conveyor already computes (the IntegritySentinel
  verdict, acceptance calibration, baseline health, replay divergence, and the
  Genome's historical pass rate) into a calibrated estimate of whether a *passed*
  gate verdict is trustworthy, plus the band that estimate falls into:

    * `:auto_accept` — confident enough to merge unattended;
    * `:abstain`     — passed the stages but not calibrated-confident; route to
      the human (`Slice` -> `:parked`). Abstain is fail-closed; it never merges.

  TrustScore only adjudicates *passed* gates. A stage failure already produced
  `passed? == false` upstream, so there is no `fail` band here.

  Determinism boundary: this is a conductor-side computation over recorded
  evidence with no I/O, no clock, and no RNG. No agent input enters the score.

  > NOT YET IMPLEMENTED. The behavioural contract lives in
  > `test/conveyor/gate/trust_score_test.exs` (TDD red). See
  > `docs/2_implementation_plans/ADR-23-RELIABILITY-ENGINE-PLAN.md`.
  """

  @type band :: :auto_accept | :abstain

  @type evidence :: %{
          optional(:integrity_verdict) => String.t() | nil,
          optional(:calibration_status) => :valid | :invalid | :not_assessed,
          optional(:baseline_status) => :green | :red | :unknown,
          optional(:replay_divergence) => :none | :diverged | :unknown,
          optional(:corpus_pass_rate) => float() | nil
        }

  @type result :: %{
          score: float(),
          band: band(),
          components: %{
            integrity: float(),
            calibration: float(),
            baseline: float(),
            replay: float(),
            corpus: float()
          },
          thresholds: %{auto_accept: float()},
          policy_digest: String.t()
        }

  @doc """
  Evaluate the calibrated trust of a passed gate verdict from recorded evidence.

  `opts` may carry `:thresholds` and `:weights` overrides; both contribute to the
  content-addressed `:policy_digest`. Pure: identical inputs yield identical
  output.
  """
  @spec evaluate(evidence(), keyword()) :: result()
  def evaluate(evidence, opts \\ []) when is_map(evidence) and is_list(opts) do
    # ADR-23 STUB (dr1m.1): the real calibrated fusion is unimplemented; every
    # passed gate scores 0.0 and abstains. The behavioural contract in
    # test/conveyor/gate/trust_score_test.exs is RED until the fusion lands.
    # (The type checker observes that the stub always abstains and will hint that
    # the RED auto-accept assertions "will never match" — that is expected and
    # disappears once `evaluate/2` is implemented for real.)
    auto_accept = opts |> Keyword.get(:thresholds, %{}) |> Map.get(:auto_accept, 0.9)

    %{
      score: 0.0,
      band: :abstain,
      components: %{integrity: 0.0, calibration: 0.0, baseline: 0.0, replay: 0.0, corpus: 0.0},
      thresholds: %{auto_accept: auto_accept},
      policy_digest: "sha256:stub"
    }
  end
end
