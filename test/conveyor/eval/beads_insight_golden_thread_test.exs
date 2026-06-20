defmodule Conveyor.Eval.BeadsInsightGoldenThreadTest do
  @moduledoc """
  First Light — M1a loop-integrity + M4 gate-discrimination, on the REAL Beads
  Insight plan (samples/beads_insight).

  Drives the whole 7-slice plan through the existing Golden-Thread harness for
  each canary case: RunSlice over the agent station (ReferenceSolution applies the
  case patch) → verify station (real pytest via the Toolchain Runner) → the
  deterministic gate. Asserts the gate DISCRIMINATES:

    * the complete reference solution PASSES  (loop_integrity — a known-good diff
      MUST pass; if it fails, the loop is broken, not the agent), and
    * every behavioral mutant FAILS           (false_pass_rate == 0 — a bad diff
      MUST be caught; a false-pass would launder broken work as verified).

  $0, deterministic. Mutants live in `samples/beads_insight/.conveyor/canary/`.
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Eval.{BridgeFixtures, GoldenThread}

  @moduletag :eval
  @moduletag timeout: 600_000

  @sample Path.expand("../../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @canary "samples/beads_insight/.conveyor/canary"

  # {id, repo-root-relative patch, expected gate verdict}
  defp cases do
    [
      {"reference_full", "#{@canary}/reference_full.patch", :pass},
      {"ready_includes_blocked", "#{@canary}/mutants/ready_includes_blocked.patch", :fail},
      {"cycles_missed", "#{@canary}/mutants/cycles_missed.patch", :fail},
      {"epics_miscount", "#{@canary}/mutants/epics_miscount.patch", :fail}
    ]
  end

  test "the Beads Insight gate discriminates: reference PASSES, behavioral mutants FAIL (false_pass=0)" do
    results =
      for {id, patch, expected} <- cases() do
        fixture =
          BridgeFixtures.sample_fixture!(
            label: "bi-#{id}",
            sample_path: @sample,
            plan_path: @plan_path,
            patch_ref: patch
          )

        report = GoldenThread.run_pipeline(fixture)

        assert report.run_status == :succeeded,
               "RunSlice failed for #{id}: #{inspect(report.findings)}"

        case expected do
          :pass ->
            assert report.gate_passed,
                   "#{id} (reference) must PASS the gate (loop_integrity); findings: #{inspect(report.findings)}"

          :fail ->
            refute report.gate_passed,
                   "#{id} (mutant) must FAIL the gate — a FALSE PASS would launder broken work as verified"
        end

        {id, expected, report.gate_passed}
      end

    # loop_integrity: the known-good reference passed.
    assert Enum.any?(results, fn {id, _, passed?} -> id == "reference_full" and passed? end),
           "loop_integrity FAILED: the reference solution did not pass the gate"

    # false_pass_rate == 0: every behavioral mutant was caught.
    mutants = Enum.filter(results, fn {_, expected, _} -> expected == :fail end)
    false_passes = Enum.count(mutants, fn {_, _, passed?} -> passed? end)

    assert length(mutants) == 3
    assert false_passes == 0, "#{false_passes}/#{length(mutants)} mutants FALSE-PASSED the gate"
  end
end
