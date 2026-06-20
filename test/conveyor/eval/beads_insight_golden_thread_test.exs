defmodule Conveyor.Eval.BeadsInsightGoldenThreadTest do
  @moduledoc """
  First Light — M1a loop-integrity proof.

  Drives the REAL Beads Insight plan (samples/beads_insight) through the existing
  Golden-Thread harness with the complete reference solution
  (`.conveyor/canary/reference_full.patch`): RunSlice over the agent station
  (ReferenceSolution applies the patch) → verify station (real pytest via the
  Toolchain Runner) → the deterministic gate. The known-good reference MUST pass —
  if it does not, the LOOP is broken (not the agent). $0, deterministic.
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Eval.{BridgeFixtures, GoldenThread}

  @moduletag :eval
  @moduletag timeout: 600_000

  @sample Path.expand("../../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @reference_patch "samples/beads_insight/.conveyor/canary/reference_full.patch"

  test "the Beads Insight plan drives the full loop to a real gate-pass (loop_integrity)" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "beads-insight-ref",
        sample_path: @sample,
        plan_path: @plan_path,
        patch_ref: @reference_patch
      )

    report = GoldenThread.run_pipeline(fixture)

    assert report.run_status == :succeeded,
           "RunSlice failed: #{inspect(report.findings)}"

    assert report.verification_status == "passed",
           "pytest should be green under the reference solution; got #{inspect(report.verification_status)}"

    assert report.gate_passed,
           "the reference solution must PASS the gate (loop_integrity); findings: #{inspect(report.findings)}"
  end
end
