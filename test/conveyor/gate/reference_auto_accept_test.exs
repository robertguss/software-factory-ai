defmodule Conveyor.Gate.ReferenceAutoAcceptTest do
  @moduledoc """
  M4-A6 — the weight/threshold re-tuning **brake**, encoded as an executable
  anchor rather than a runtime subsystem.

  The known-good reference must auto-accept at **every** M4 stage. This test pins
  the reference score arithmetic so that "re-tune the threshold to rescue a
  reference that abstained for a real reason" is impossible to do silently: any
  weight/threshold change that moves these numbers fails here and must be justified
  (PR body + anchor update + a re-run gauntlet asserting `false_pass_rate == 0`).

  Integrity note (M4: un-laundered): the reference's integrity `"trustworthy"` is now
  *earned* — the verify station's real `source_mutation` probe (the only one required on
  `:local`) is clean. A genuine production-source mutation makes it `"untrustworthy"`
  (0.0) -> abstain; a `"suspect"` verdict (0.5) drops the reference to 0.775 -> abstain.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Gate.TrustScore

  # The §4 anchor: auto-accept threshold the reference must clear.
  @anchor_score_floor 0.9

  # The reference: integrity real-and-"trustworthy" (clean source_mutation probe),
  # calibration + baseline real-and-green, replay none, corpus cold-start (nil -> 0.5).
  # Scores 0.925.
  defp current_reference_evidence do
    %{
      integrity_verdict: "trustworthy",
      calibration_status: :valid,
      baseline_status: :green,
      replay_divergence: :none,
      corpus_pass_rate: nil
    }
  end

  describe "the reference auto-accepts at the current stage" do
    test "current reference clears the anchor and auto-accepts" do
      r = TrustScore.evaluate(current_reference_evidence())

      assert r.band == :auto_accept
      assert r.score >= r.thresholds.auto_accept
      assert r.thresholds.auto_accept == @anchor_score_floor
      assert_in_delta r.score, 0.925, 1.0e-9
    end
  end

  describe "the anchor table (weights 0.30/0.20/0.20/0.15/0.15, threshold 0.9)" do
    # {label, integrity, calibration, baseline, replay, corpus, want_score, want_band}
    @anchor_rows [
      {"all-green, cold-start corpus (nil->0.5)", "trustworthy", :valid, :green, :none, nil,
       0.925, :auto_accept},
      {"all-green, corpus 0.95", "trustworthy", :valid, :green, :none, 0.95, 0.9925,
       :auto_accept},
      {"all-green, corpus 1.0", "trustworthy", :valid, :green, :none, 1.0, 1.0, :auto_accept}
    ]

    for {label, integ, calib, base, replay, corpus, want_score, want_band} <- @anchor_rows do
      test "row: #{label}" do
        r =
          TrustScore.evaluate(%{
            integrity_verdict: unquote(integ),
            calibration_status: unquote(calib),
            baseline_status: unquote(base),
            replay_divergence: unquote(replay),
            corpus_pass_rate: unquote(corpus)
          })

        assert_in_delta r.score, unquote(want_score), 1.0e-9
        assert r.band == unquote(want_band)
      end
    end
  end

  describe "a suspect integrity verdict parks the reference (the 0.775 guard)" do
    test "a 'suspect' integrity (0.5) with everything else green abstains" do
      # Integrity "suspect" scores 0.5; everything else green. 0.775 < 0.9 -> abstain.
      r =
        TrustScore.evaluate(%{
          integrity_verdict: "suspect",
          calibration_status: :valid,
          baseline_status: :green,
          replay_divergence: :none,
          corpus_pass_rate: nil
        })

      assert_in_delta r.score, 0.775, 1.0e-9
      assert r.band == :abstain
    end
  end
end
