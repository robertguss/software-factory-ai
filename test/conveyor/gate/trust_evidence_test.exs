defmodule Conveyor.Gate.TrustEvidenceTest do
  @moduledoc """
  ADR-23 — the evidence-threading layer that turns a slice run's signals into
  `TrustScore` evidence. Asserts the safe-rollout contract: a passed gate abstains
  only on a recognized negative signal; unmeasured signals are non-blocking.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Gate.TrustEvidence
  alias Conveyor.Gate.TrustScore

  defp band(output),
    do: output |> TrustEvidence.from_run_output() |> TrustScore.evaluate() |> Map.fetch!(:band)

  describe "from_run_output/1 -> TrustScore band" do
    test "valid calibration + passed baseline auto-accepts" do
      assert band(%{
               "test_pack_calibration" => %{"status" => "valid"},
               "baseline_health_status" => "passed"
             }) == :auto_accept
    end

    test "invalid calibration abstains" do
      assert band(%{
               "test_pack_calibration" => %{"status" => "invalid"},
               "baseline_health_status" => "passed"
             }) == :abstain
    end

    test "failed baseline abstains" do
      assert band(%{
               "test_pack_calibration" => %{"status" => "valid"},
               "baseline_health_status" => "failed"
             }) == :abstain
    end

    test "a suspect integrity verdict in the output abstains" do
      assert band(%{
               "test_pack_calibration" => %{"status" => "valid"},
               "baseline_health_status" => "passed",
               "integrity_verdict" => "suspect"
             }) == :abstain
    end

    test "empty / unmeasured output is non-blocking (auto-accept)" do
      assert band(%{}) == :auto_accept
    end
  end

  describe "assemble/1 defaults" do
    test "unmeasured signals default to non-blocking" do
      assert TrustEvidence.assemble(%{}) == %{
               integrity_verdict: "trustworthy",
               calibration_status: :valid,
               baseline_status: :green,
               replay_divergence: :none,
               corpus_pass_rate: nil
             }
    end

    test "recognized negatives map to blocking values" do
      evidence =
        TrustEvidence.assemble(%{calibration: :invalid, baseline: :failed, replay: :diverged})

      assert evidence.calibration_status == :invalid
      assert evidence.baseline_status == :red
      assert evidence.replay_divergence == :diverged
    end

    test "a float corpus pass rate is carried through" do
      assert TrustEvidence.assemble(%{corpus_pass_rate: 0.8}).corpus_pass_rate == 0.8
    end
  end
end
