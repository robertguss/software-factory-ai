defmodule Conveyor.Gate.TrustEvidenceTest do
  @moduledoc """
  ADR-23 / M4-A1 — the evidence-threading layer that turns a slice run's signals
  into `TrustScore` evidence. Asserts the **fail-closed** contract: an
  always-assessable signal (calibration, baseline) that is expected but absent
  abstains; a producer may declare a signal not-assessable to keep it non-blocking.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Gate.TrustEvidence
  alias Conveyor.Gate.TrustScore

  defp band(output),
    do: output |> TrustEvidence.from_run_output() |> TrustScore.evaluate() |> Map.fetch!(:band)

  describe "from_run_output/1 -> TrustScore band" do
    test "valid calibration + passed baseline + trustworthy integrity auto-accepts" do
      assert band(%{
               "test_pack_calibration" => %{"status" => "valid"},
               "baseline_health_status" => "passed",
               "integrity_verdict" => "trustworthy"
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

    # M4-A1: the keystone inversion. These used to auto-accept (the laundering leak).
    test "absent calibration fails closed (abstains)" do
      assert band(%{"baseline_health_status" => "passed"}) == :abstain
    end

    test "absent baseline fails closed (abstains)" do
      assert band(%{"test_pack_calibration" => %{"status" => "valid"}}) == :abstain
    end

    test "empty / unmeasured output fails closed (abstains)" do
      assert band(%{}) == :abstain
    end
  end

  describe "from_run_output/1 anti-vacuity guard" do
    test "absent always-assessable signals route to their abstaining token, not a passing one" do
      evidence = TrustEvidence.from_run_output(%{})

      assert evidence.calibration_status == :not_assessed
      assert evidence.baseline_status == :unknown
      assert evidence.integrity_verdict == "not_assessed"
    end
  end

  describe "assemble/1 defaults" do
    test "unmeasured calibration + baseline + integrity fail closed; absent replay is :baseline_absent" do
      assert TrustEvidence.assemble(%{}) == %{
               integrity_verdict: "not_assessed",
               calibration_status: :not_assessed,
               baseline_status: :unknown,
               replay_divergence: :baseline_absent,
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

    test "a measured-good calibration + baseline pass through" do
      evidence = TrustEvidence.assemble(%{calibration: "valid", baseline: "passed"})

      assert evidence.calibration_status == :valid
      assert evidence.baseline_status == :green
    end

    test "a float corpus pass rate is carried through" do
      assert TrustEvidence.assemble(%{corpus_pass_rate: 0.8}).corpus_pass_rate == 0.8
    end
  end

  describe "declared-not-assessable (producer says N/A on this backend)" do
    test "a declared signal routes to its neutral middle token, not a bad one" do
      evidence = TrustEvidence.assemble(%{declared_not_assessable: [:replay]})

      assert evidence.replay_divergence == :baseline_absent
    end

    test "from_run_output threads the trust_not_assessable output key" do
      evidence =
        TrustEvidence.from_run_output(%{
          "test_pack_calibration" => %{"status" => "valid"},
          "baseline_health_status" => "passed",
          "trust_not_assessable" => ["replay"]
        })

      assert evidence.replay_divergence == :baseline_absent
    end
  end
end
