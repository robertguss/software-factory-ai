defmodule Conveyor.Eval.SourceMutationProducerTest do
  @moduledoc """
  ADR-23 source-mutation producer — real pytest over a copy of
  samples/beads_insight (whose venv builds in this env; tasks_service's does not).
  Tagged :eval. Detects production source the *test run* rewrote (an anti-vacuity
  cheat), independent of whether the suite passes.
  """
  use ExUnit.Case, async: false

  alias Conveyor.Eval.ToolchainRunner
  alias Conveyor.Gate.IntegrityEvidence

  @moduletag :eval
  @moduletag timeout: 300_000

  @sample Path.expand("../../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")

  setup do
    {:ok, plan: YamlElixir.read_from_file!(@plan_path)}
  end

  test "a clean run reports no mutated production paths", %{plan: plan} do
    ws = workspace!()

    result = ToolchainRunner.verification_result(ws, plan, source_root: "src")

    assert get_in(result, [
             "integrity_observations",
             "source_mutation",
             "mutated_production_paths"
           ]) ==
             []
  end

  test "a test rewriting production source during the run is caught -> untrustworthy", %{
    plan: plan
  } do
    ws = workspace!()
    plant_cheating_test!(ws)

    result = ToolchainRunner.verification_result(ws, plan, source_root: "src")

    mutated =
      get_in(result, ["integrity_observations", "source_mutation", "mutated_production_paths"])

    assert "src/br_insight/loader.py" in mutated

    assert IntegrityEvidence.verdict(result["integrity_observations"],
             required_probes: ["source_mutation"]
           ) == "untrustworthy"
  end

  defp workspace! do
    dst =
      Path.join(
        System.tmp_dir!(),
        "conveyor_srcmut_ws_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.mkdir_p!(dst)

    {_, 0} =
      System.cmd("rsync", [
        "-a",
        "--exclude",
        ".venv",
        "--exclude",
        ".pytest_cache",
        "--exclude",
        "__pycache__",
        "--exclude",
        ".git",
        @sample <> "/",
        dst <> "/"
      ])

    on_exit(fn -> File.rm_rf(dst) end)
    dst
  end

  # A test that rewrites a production source file mid-run — the cheat to catch.
  defp plant_cheating_test!(ws) do
    File.write!(Path.join(ws, "tests/test_zz_cheat.py"), """
    def test_zz_cheat():
        with open("src/br_insight/loader.py", "a") as handle:
            handle.write("\\n# mutated during the test run\\n")
        assert True
    """)
  end
end
