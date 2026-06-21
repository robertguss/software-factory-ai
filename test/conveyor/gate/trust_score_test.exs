defmodule Conveyor.Gate.TrustScoreTest do
  @moduledoc """
  ADR-23 TDD skeletons for the pure `Conveyor.Gate.TrustScore`.

  These are the executable contract for the Reliability Engine (ADR-23 Part A —
  the pure `TrustScore`). Part B (the `Finalizer` `:abstain` wiring) is deferred;
  see the plan.

  Plan: docs/2_implementation_plans/ADR-23-RELIABILITY-ENGINE-PLAN.md
  """
  use ExUnit.Case, async: true

  alias Conveyor.Gate.TrustScore

  # The known-good reference solution's evidence: everything is green and the
  # integrity oracle says trustworthy. This MUST auto-accept (loop_integrity).
  defp reference_evidence do
    %{
      integrity_verdict: "trustworthy",
      calibration_status: :valid,
      baseline_status: :green,
      replay_divergence: :none,
      corpus_pass_rate: 0.95
    }
  end

  describe "band partition" do
    test "trustworthy + fully-green evidence auto-accepts with a high score" do
      result = TrustScore.evaluate(reference_evidence())

      assert result.band == :auto_accept
      assert result.score >= result.thresholds.auto_accept
      assert result.score > 0.8
    end

    test "loop_integrity invariant: the known-good reference must auto-accept" do
      # If the reference solution abstains, calibration is broken — this is a
      # release-blocking miscalibration, not a normal abstain (ADR-23).
      assert TrustScore.evaluate(reference_evidence()).band == :auto_accept
    end

    test "suspect integrity abstains even when stages are green" do
      evidence = %{reference_evidence() | integrity_verdict: "suspect"}
      assert TrustScore.evaluate(evidence).band == :abstain
    end

    test "untrustworthy integrity abstains with a low score" do
      evidence = %{reference_evidence() | integrity_verdict: "untrustworthy"}
      result = TrustScore.evaluate(evidence)

      assert result.band == :abstain
      assert result.score < result.thresholds.auto_accept
    end

    test "thin / not_assessed evidence abstains (conservative bootstrap)" do
      thin = %{
        integrity_verdict: "not_assessed",
        calibration_status: :not_assessed,
        baseline_status: :unknown,
        replay_divergence: :unknown,
        corpus_pass_rate: nil
      }

      assert TrustScore.evaluate(thin).band == :abstain
    end

    test "evaluation-surface replay divergence abstains" do
      evidence = %{reference_evidence() | replay_divergence: :diverged}
      assert TrustScore.evaluate(evidence).band == :abstain
    end
  end

  describe "purity and calibration properties" do
    test "is deterministic: identical evidence yields identical results" do
      e = reference_evidence()
      assert TrustScore.evaluate(e) == TrustScore.evaluate(e)
    end

    test "strengthening every component lands :auto_accept (monotonicity)" do
      strong = %{
        reference_evidence()
        | integrity_verdict: "trustworthy",
          calibration_status: :valid,
          baseline_status: :green,
          replay_divergence: :none,
          corpus_pass_rate: 0.99
      }

      assert TrustScore.evaluate(strong).band == :auto_accept
    end

    test "always returns the full component breakdown" do
      result = TrustScore.evaluate(reference_evidence())

      assert %{
               integrity: _,
               calibration: _,
               baseline: _,
               replay: _,
               corpus: _
             } = result.components
    end
  end

  describe "content-addressed policy" do
    test "policy_digest is stable for fixed weights and thresholds" do
      a = TrustScore.evaluate(reference_evidence())
      b = TrustScore.evaluate(reference_evidence())
      assert a.policy_digest == b.policy_digest
    end

    test "policy_digest changes when thresholds change" do
      base = TrustScore.evaluate(reference_evidence())
      tightened = TrustScore.evaluate(reference_evidence(), thresholds: %{auto_accept: 0.99})

      refute base.policy_digest == tightened.policy_digest
    end
  end
end
