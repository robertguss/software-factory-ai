defmodule Conveyor.Eval.MutantGauntletTest do
  use ExUnit.Case, async: false

  alias Conveyor.Eval.MutantGauntlet

  @moduletag :eval
  @moduletag timeout: 300_000
  @beads_manifest "samples/beads_insight/.conveyor/canary/mutants.json"
  @beads_plan "samples/beads_insight/conveyor.plan.yml"

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

  test "Beads Insight canaries cover every slice with scoped locked ACs" do
    report =
      MutantGauntlet.run(
        manifest_path: @beads_manifest,
        plan_path: @beads_plan,
        venv_bin: pytest_venv_bin()
      )

    assert report["known_good_passed"] == true
    assert report["real_exec_mutants"] == 7
    assert report["caught"] == 7
    assert report["false_pass_rate"] == 0.0

    mutants = Enum.filter(report["cases"], &(&1["kind"] == "mutant"))

    assert mutants |> Enum.map(& &1["slice_id"]) |> Enum.sort() ==
             ~w(SLICE-001 SLICE-002 SLICE-003 SLICE-004 SLICE-005 SLICE-006 SLICE-007)

    for mutant <- mutants do
      refute mutant["gate_passed"], "mutant #{mutant["id"]} slipped through"
      assert mutant["acceptance_refs"] != []
      assert mutant["test_refs"] != []
      assert "test_execution" in mutant["caught_by_stage"]
    end
  end

  defp pytest_venv_bin do
    case Path.expand("samples/tasks_service/.venv/bin") do
      bin when is_binary(bin) ->
        if File.dir?(bin), do: bin, else: nil
    end
  end
end
