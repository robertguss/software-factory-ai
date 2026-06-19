defmodule Conveyor.Eval.GoldenThreadTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Eval.{BridgeFixtures, CompilerProperties, GoldenThread}
  alias Conveyor.Planning.GraphAnalyses

  @moduletag :eval
  @moduletag timeout: 600_000

  defp cases do
    base = "samples/tasks_service/.conveyor/canary"

    [
      {"known_good", "#{base}/known_good.patch", :pass},
      {"patch_unknown_id_returns_200", "#{base}/mutants/patch_unknown_id_returns_200.patch",
       :fail},
      {"completed_not_persisted_to_list", "#{base}/mutants/completed_not_persisted_to_list.patch",
       :fail},
      {"default_completed_missing", "#{base}/mutants/default_completed_missing.patch", :fail}
    ]
  end

  test "a human plan drives the full pipeline to a real verdict: known_good PASS, behavioral mutants FAIL" do
    results =
      for {id, patch, expected} <- cases() do
        fixture = BridgeFixtures.sample_fixture!(label: "gt-#{id}", patch_ref: patch)
        report = GoldenThread.run_pipeline(fixture)

        assert report.run_status == :succeeded,
               "RunSlice failed for #{id}: #{inspect(report.findings)}"

        case expected do
          :pass -> assert report.gate_passed, "#{id} should PASS the gate"
          :fail -> refute report.gate_passed, "#{id} should FAIL the gate (false PASS)"
        end

        {id, report.gate_passed}
      end

    known_good_passed? =
      Enum.any?(results, fn {id, passed?} -> id == "known_good" and passed? end)

    mutants = Enum.reject(results, fn {id, _} -> id == "known_good" end)
    mutants_failed = Enum.count(mutants, fn {_, passed?} -> not passed? end)

    assert known_good_passed?
    assert mutants_failed == 3

    GoldenThread.emit!(%{
      "known_good_passed" => known_good_passed?,
      "mutants_failed" => mutants_failed,
      "mutants_total" => length(mutants),
      "traceability_preserved" => traceability_preserved?()
    })
  end

  test "the lowering preserves slice->AC->obligation traceability (no orphan obligation)" do
    assert traceability_preserved?()
  end

  defp traceability_preserved? do
    analysis = GraphAnalyses.run(CompilerProperties.graph_fixture(1, []))

    analysis.status == :passed and
      not Enum.any?(analysis.findings, &(&1[:rule_key] == "traceability_gap"))
  end
end
