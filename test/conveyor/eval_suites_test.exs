defmodule Conveyor.EvalSuitesTest do
  use ExUnit.Case, async: true

  alias Conveyor.EvalSuites

  test "phase-1 eval suites produce a stable passing report" do
    report = EvalSuites.run!()

    assert report["schema_version"] == "conveyor.eval_report@1"
    assert report["suite_version"] == "phase1-evals@1"
    assert report["passed"]
    assert report["suite_count"] == 5
    assert report["case_count"] == 9

    suites = Map.new(report["suites"], &{&1["id"], &1})
    assert suites["prompt_injection"]["passed"]
    assert suites["artifact_integrity"]["passed"]
  end

  test "phase-1 eval report is stable across runs" do
    assert EvalSuites.run!() == EvalSuites.run!()
  end

  test "report exposes observed categories for prompt injection and artifact integrity" do
    report = EvalSuites.run!()

    cases =
      report["suites"]
      |> Enum.flat_map(& &1["cases"])
      |> Map.new(&{&1["id"], &1})

    assert "untrusted_instruction_followed" in cases["artifact_followed_untrusted_instruction"][
             "observed_categories"
           ]

    assert cases["missing_verification_log"]["observed_category"] == "missing_required_artifact"
    assert "bundle_root_mismatch" in cases["tampered_manifest_root"]["observed_categories"]
    assert cases["stale_canary_ref"]["observed_category"] == "stale_canary"
  end
end
