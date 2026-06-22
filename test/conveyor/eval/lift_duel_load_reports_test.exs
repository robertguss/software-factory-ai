defmodule Conveyor.Eval.LiftDuelLoadReportsTest do
  # Pure file IO — no DB, no agent, NOT :eval-tagged, so this runs in the default CI
  # suite and guards the `mix conveyor.eval.lift` crash (dr1m.12 / ROADMAP M0).
  use ExUnit.Case, async: true

  alias Conveyor.Eval.LiftDuel

  setup do
    dir = Path.join(System.tmp_dir!(), "lift-load-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "keeps only eval_lift reports and skips sibling non-report JSON (usage.json)", %{dir: dir} do
    File.write!(
      Path.join(dir, "seed.json"),
      Jason.encode!(%{"schema_version" => "conveyor.eval_lift@1", "lift" => %{}})
    )

    # `usage.json` is a `conveyor.agent_usage@1` ARRAY, not a report. Before the fix,
    # load_reports decoded it and the mix task handed it to metrics/1 → crash.
    File.write!(
      Path.join(dir, "usage.json"),
      Jason.encode!([%{"schema_version" => "conveyor.agent_usage@1", "tokens" => 1}])
    )

    reports = LiftDuel.load_reports(dir)

    assert [{"seed", report}] = reports
    assert report["schema_version"] == "conveyor.eval_lift@1"
    refute Enum.any?(reports, fn {name, _} -> name == "usage" end)
  end

  test "returns [] for a missing directory" do
    missing = Path.join(System.tmp_dir!(), "nope-#{System.unique_integer([:positive])}")
    assert LiftDuel.load_reports(missing) == []
  end
end
