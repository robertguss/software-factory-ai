defmodule Conveyor.Recovery.FailureFingerprintTest do
  @moduledoc "rt6k.3: failure fingerprint stability + difference sensitivity."
  use ExUnit.Case, async: true

  alias Conveyor.Gate
  alias Conveyor.Recovery.FailureFingerprint

  defp gate(findings),
    do: %Gate.Result{
      status: :failed,
      passed?: false,
      stages: [],
      findings: findings,
      gate_result_attrs: %{}
    }

  @finding %{
    "category" => "acceptance_mapping",
    "stage" => "verify",
    "acceptance_criterion_id" => "AC-003",
    "path" => "test/foo_test.exs"
  }

  test "same failure yields the same digest across calls" do
    assert FailureFingerprint.compute(gate([@finding])) ==
             FailureFingerprint.compute(gate([@finding]))
  end

  test "digest ignores noise fields (message, severity, duration, timestamp)" do
    noisy =
      Map.merge(@finding, %{
        "message" => "AC-003 was not met at 2026-07-02T10:00:00Z",
        "severity" => "blocking",
        "duration_ms" => 4213,
        "tmp_path" => "/tmp/build-9931"
      })

    assert FailureFingerprint.compute(gate([noisy])) ==
             FailureFingerprint.compute(gate([@finding]))
  end

  test "finding order does not change the digest" do
    other = Map.put(@finding, "acceptance_criterion_id", "AC-001")

    assert FailureFingerprint.compute(gate([@finding, other])) ==
             FailureFingerprint.compute(gate([other, @finding]))
  end

  test "a different failing criterion yields a different digest" do
    other = Map.put(@finding, "acceptance_criterion_id", "AC-999")

    refute FailureFingerprint.compute(gate([@finding])) ==
             FailureFingerprint.compute(gate([other]))
  end

  test "a different gate status yields a different digest" do
    refute FailureFingerprint.compute(:failed, [@finding]) ==
             FailureFingerprint.compute(:policy_blocked, [@finding])
  end
end
