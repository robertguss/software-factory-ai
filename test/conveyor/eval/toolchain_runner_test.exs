defmodule Conveyor.Eval.ToolchainRunnerTest do
  # Real pytest execution against a copy of samples/tasks_service. Tagged :eval so
  # it can be scoped in/out of fast unit runs. Uses the sample's committed .venv
  # when present (offline, fast); otherwise F1 builds+caches a venv from
  # requirements.lock (the CI path), which can take a while on first run.
  use ExUnit.Case, async: false

  alias Conveyor.Eval.ToolchainRunner

  @moduletag :eval
  @moduletag timeout: 300_000

  @sample Path.expand("../../../samples/tasks_service", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @mutant_unknown_404 Path.join(
                        @sample,
                        ".conveyor/canary/mutants/patch_unknown_id_returns_200.patch"
                      )
  @unknown_404_nodeid "tests/test_tasks_api.py::test_complete_unknown_task_returns_404"

  setup do
    {:ok, plan: YamlElixir.read_from_file!(@plan_path)}
  end

  test "clean workspace: all 7 pytest nodeids pass and gate-shaped suites are produced", %{
    plan: plan
  } do
    ws = workspace!()

    result = ToolchainRunner.verification_result(ws, plan, opts())

    assert result["status"] == "passed"
    assert is_binary(result["result_digest"])

    baseline = suite(result, "baseline_regression")
    tests = suite_tests(baseline)

    assert length(tests) == 7
    assert Enum.all?(tests, &(&1["status"] == "passed"))
    assert @unknown_404_nodeid in Enum.map(tests, & &1["id"])

    # Both gate-required suites are present.
    assert suite(result, "acceptance_locked")
  end

  test "mutant patch (unknown id returns 200): the 404 acceptance test fails", %{plan: plan} do
    ws = workspace!()
    apply_patch!(ws, @mutant_unknown_404)

    result = ToolchainRunner.verification_result(ws, plan, opts())

    assert result["status"] == "failed"

    failed =
      result
      |> suite("baseline_regression")
      |> suite_tests()
      |> Enum.find(&(&1["id"] == @unknown_404_nodeid))

    assert failed["status"] == "failed"
  end

  test "determinism: two consecutive runs produce a byte-identical result_digest", %{plan: plan} do
    ws = workspace!()

    r1 = ToolchainRunner.verification_result(ws, plan, opts())
    r2 = ToolchainRunner.verification_result(ws, plan, opts())

    assert r1["result_digest"] == r2["result_digest"]
    assert r1["result_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  # --- helpers --------------------------------------------------------------

  # Prefer the sample's committed .venv (offline); fall back to F1 building one.
  defp opts do
    venv_bin = Path.join(@sample, ".venv/bin")
    if File.dir?(venv_bin), do: [venv_bin: venv_bin], else: []
  end

  defp workspace! do
    dst =
      Path.join(
        System.tmp_dir!(),
        "conveyor_eval_ws_" <> Integer.to_string(System.unique_integer([:positive]))
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

  defp apply_patch!(ws, patch_path) do
    {_out, 0} =
      System.cmd("patch", ["-p3", "-f", "-d", ws, "-i", patch_path], stderr_to_stdout: true)
  end

  defp suite(result, kind), do: Enum.find(result["suites"], &(&1["suite_kind"] == kind))

  defp suite_tests(suite) do
    suite["commands"]
    |> Enum.flat_map(fn c -> c["attempts"] end)
    |> Enum.flat_map(fn a -> a["tests"] end)
  end
end
