defmodule Conveyor.Eval.MutantGauntletTest do
  use ExUnit.Case, async: false

  alias Conveyor.Eval.MutantGauntlet

  @moduletag :eval
  @moduletag timeout: 300_000

  setup_all do
    {:ok, report: MutantGauntlet.run()}
  end

  test "known_good passes the gate on real evidence", %{report: report} do
    assert report["known_good_passed"] == true
  end

  test "every behavioral mutant is caught by test_execution (false_pass_rate = 0)", %{
    report: report
  } do
    assert report["real_exec_mutants"] == 3
    assert report["caught"] == 3
    assert report["false_pass_rate"] == 0.0
    assert report["mutant_catch_rate"] == 1.0

    for c <- report["cases"], c["kind"] == "mutant" do
      refute c["gate_passed"], "mutant #{c["id"]} slipped through (false PASS)"
      assert "test_execution" in c["caught_by_stage"]
    end
  end

  test "the 5 static-stage mutants are recorded as deferred to B2", %{report: report} do
    assert length(report["deferred_static_stage"]) == 5
    assert "forbidden_policy_edit" in report["deferred_static_stage"]
    assert "test_weakened_or_deleted" in report["deferred_static_stage"]
  end

  test "metrics: false_pass_rate is blocking@0, mutant_catch_rate@1", %{report: report} do
    [fpr, mcr] = MutantGauntlet.metrics(report)

    assert fpr["key"] == "false_pass_rate"
    assert fpr["blocking"] == true
    assert fpr["status"] == "ok"

    assert mcr["key"] == "mutant_catch_rate"
    assert mcr["value"] == 1.0
  end
end
