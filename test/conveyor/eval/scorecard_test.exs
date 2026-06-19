defmodule Conveyor.Eval.ScorecardTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Conveyor.Eval.Scorecard

  @moduletag :eval

  defp metric(key, status, blocking, suite \\ "e1") do
    %{
      "schema_version" => "conveyor.eval_metric@1",
      "key" => key,
      "suite" => suite,
      "value" => 0,
      "target" => 0,
      "blocking" => blocking,
      "status" => status
    }
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:jsv)
    :ok
  end

  test "build is deterministic, schema-valid, and sorts metrics by key" do
    metrics = [metric("z_metric", "ok", false), metric("a_metric", "ok", false)]
    s1 = Scorecard.build(metrics, revision: "abc123")
    s2 = Scorecard.build(metrics, revision: "abc123")

    assert s1 == s2
    assert s1["scorecard_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    assert Enum.map(s1["metrics"], & &1["key"]) == ["a_metric", "z_metric"]
    assert Scorecard.validate(s1) == :ok
    assert Scorecard.healthy?(s1)
    assert s1["canonical_blockers"] == []
  end

  test "a blocking metric flips healthy? and lands in canonical_blockers" do
    metrics = [metric("false_pass_rate", "blocking", true), metric("ok_metric", "ok", false)]
    s = Scorecard.build(metrics, revision: "abc123")

    refute Scorecard.healthy?(s)
    assert Enum.map(s["canonical_blockers"], & &1["key"]) == ["false_pass_rate"]
    assert Scorecard.validate(s) == :ok
  end

  test "zero inputs degrade to an empty, healthy, valid scorecard" do
    s = Scorecard.build([], revision: "abc123")
    assert s["metrics"] == []
    assert s["healthy?"] == true
    assert Scorecard.validate(s) == :ok
  end

  describe "mix conveyor.eval.scorecard --gate" do
    setup do
      dir =
        Path.join(
          System.tmp_dir!(),
          "eval_sc_inputs_" <> Integer.to_string(System.unique_integer([:positive]))
        )

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir}
    end

    test "exits success (0) when healthy", %{dir: dir} do
      write_metric!(dir, metric("k", "ok", false))
      assert run_task(["--gate", "--inputs", dir, "--revision", "r"]) == 0
    end

    test "exits eval-false-negative (6) when a blocking metric is present", %{dir: dir} do
      write_metric!(dir, metric("false_pass_rate", "blocking", true))
      assert run_task(["--gate", "--inputs", dir, "--revision", "r"]) == 6
    end

    test "without --gate, a blocking metric still exits 0 (report-only)", %{dir: dir} do
      write_metric!(dir, metric("false_pass_rate", "blocking", true))
      assert run_task(["--inputs", dir, "--revision", "r"]) == 0
    end
  end

  defp write_metric!(dir, m),
    do: File.write!(Path.join(dir, "#{m["key"]}.json"), Jason.encode!(m))

  defp run_task(args) do
    test_pid = self()
    Process.put(:conveyor_eval_scorecard_exit_fun, fn code -> send(test_pid, {:exit, code}) end)
    capture_io(fn -> Mix.Tasks.Conveyor.Eval.Scorecard.run(args) end)
    assert_receive {:exit, code}
    code
  end
end
