defmodule Conveyor.Gate.EmptyAcceptanceSuiteTest do
  @moduledoc """
  M4-A7d / dr1m.7 — an acceptance suite that ran ZERO tests must FAIL the gate, even if
  it (falsely) reports "passed". Closes the empty-acceptance false-PASS at the gate-stage
  backstop layer (`test_execution.ex`), which checks test COUNT rather than the status
  string. (Layers 1/2 — `toolchain_runner.suite/3` and `verification_rerunner` — close it
  at the producer/rerunner level and are exercised by the eval suite.)
  """
  use ExUnit.Case, async: true

  alias Conveyor.Gate.Stages.TestExecution

  defp passing_command(test_ids) do
    %{
      "key" => "pytest",
      "status" => "passed",
      "classification" => "stable",
      "attempts" => [
        %{
          "attempt_no" => 1,
          "exit_code" => 0,
          "status" => "passed",
          "tests" => Enum.map(test_ids, &%{"id" => &1, "name" => &1, "status" => "passed"})
        }
      ]
    }
  end

  defp suite(kind, key, test_ids, status \\ "passed") do
    %{
      "suite_id" => "suite-#{key}",
      "key" => key,
      "suite_kind" => kind,
      "status" => status,
      "commands" => [passing_command(test_ids)]
    }
  end

  defp valid_calibration do
    %{"status" => "valid", "expected_failures" => ["acc_t1"]}
  end

  defp run(suites, calibration) do
    TestExecution.run(%{
      verification_result: %{"status" => "passed", "suites" => suites},
      test_pack_calibration: calibration
    })
  end

  defp categories(result), do: Enum.map(result.findings, & &1["category"])

  describe "empty acceptance suite (ran zero tests)" do
    test "falsely-passed empty acceptance suite fails the gate with an empty_acceptance_suite finding" do
      suites = [
        suite("baseline_regression", "base", ["b1"]),
        # present, status "passed", but ZERO tests parsed
        suite("acceptance_locked", "acc", [])
      ]

      result = run(suites, valid_calibration())

      assert result.status == :failed
      assert "empty_acceptance_suite" in categories(result)
    end

    test "absent acceptance_locked suite fails the gate (missing_acceptance_locked)" do
      suites = [suite("baseline_regression", "base", ["b1"])]

      result = run(suites, nil)

      assert result.status == :failed
      assert "missing_acceptance_locked" in categories(result)
    end
  end

  describe "non-empty acceptance suite" do
    test "an acceptance suite with >= 1 test and a valid base-red calibration passes" do
      suites = [
        suite("baseline_regression", "base", ["b1"]),
        suite("acceptance_locked", "acc", ["acc_t1"])
      ]

      result = run(suites, valid_calibration())

      assert result.status == :passed
      refute "empty_acceptance_suite" in categories(result)
    end
  end
end
