defmodule Conveyor.Gate.ParkReasonTest do
  @moduledoc "a3hf.1.3.1: park-reason taxonomy — classification, folding, and safe-default logging."
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Conveyor.Gate.ParkReason

  describe "from_gate_evidence/1" do
    test "calibration :invalid -> weak_acceptance_tests" do
      assert ParkReason.from_gate_evidence(%{calibration_status: :invalid}) ==
               :weak_acceptance_tests

      assert ParkReason.from_gate_evidence(%{"calibration_status" => "invalid"}) ==
               :weak_acceptance_tests
    end

    test "an unassessed trust signal -> missing_signal" do
      assert ParkReason.from_gate_evidence(%{calibration_status: :not_assessed}) ==
               :missing_signal

      assert ParkReason.from_gate_evidence(%{integrity_verdict: "not_assessed"}) ==
               :missing_signal

      assert ParkReason.from_gate_evidence(%{baseline_status: :unknown}) == :missing_signal
      assert ParkReason.from_gate_evidence(%{replay_divergence: :unknown}) == :missing_signal
    end

    test "all signals present but no named cause -> safe default, logged" do
      evidence = %{
        integrity_verdict: "suspect",
        calibration_status: :valid,
        baseline_status: :green,
        replay_divergence: :none
      }

      log = capture_log(fn -> assert ParkReason.from_gate_evidence(evidence) == :unclassified end)
      assert log =~ "unclassified cause"
    end

    test "non-map evidence -> safe default, logged" do
      log = capture_log(fn -> assert ParkReason.from_gate_evidence(nil) == :unclassified end)
      assert log =~ "unclassified cause"
    end
  end

  describe "from_signal/1" do
    test "folds the convergence sentinel's no_progress -> no_behavior_change" do
      assert ParkReason.from_signal("no_progress") == :no_behavior_change
    end

    test "an unrecognized signal -> safe default, logged" do
      log =
        capture_log(fn -> assert ParkReason.from_signal("convergence_stall") == :unclassified end)

      assert log =~ "unclassified cause"
    end
  end

  test "values/0 lists the named reasons plus the safe default" do
    assert ParkReason.default() == :unclassified
    assert :unclassified in ParkReason.values()
    assert :weak_acceptance_tests in ParkReason.values()
    assert :no_behavior_change in ParkReason.values()
    assert :missing_signal in ParkReason.values()

    # nyrl.2: scope-amendment deny reason joins the taxonomy (set explicitly, not trust-derived).
    assert :scope_denied in ParkReason.values()
  end
end
