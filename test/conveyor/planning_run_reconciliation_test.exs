defmodule Conveyor.PlanningRunReconciliationTest do
  @moduledoc "U5: exactly-once detection of an already-landed accept-commit."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.RunReconciliation

  defp git!(path, args) do
    {out, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp repo! do
    path = Path.join(System.tmp_dir!(), "conv-recon-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "t@t.invalid"])
    git!(path, ["config", "user.name", "t"])
    File.write!(Path.join(path, "base.txt"), "base")
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "base"])
    path
  end

  defp accept!(path, slice_key, file) do
    File.write!(Path.join(path, file), "work")
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "conveyor: accept #{slice_key}"])
  end

  test "an already-landed accept-commit is recovered as a passed outcome" do
    path = repo!()
    accept!(path, "SLICE-003", "s3.txt")

    assert {:already_committed, outcome} =
             RunReconciliation.reconcile_in_flight("run-x", "SLICE-003", 3, path)

    assert outcome["status"] == "passed"
    assert outcome["slice_id"] == "SLICE-003"
    assert outcome["sequence"] == 3
    assert outcome["gate_result"] == "recovered_commit"
    assert String.starts_with?(outcome["head_tree"], "sha256:")
  end

  test "no accept-commit for the slice -> re-run" do
    assert RunReconciliation.reconcile_in_flight("run-x", "SLICE-003", 3, repo!()) == :rerun
  end

  test "a different slice's accept-commit at HEAD -> re-run (no false positive)" do
    path = repo!()
    accept!(path, "SLICE-002", "s2.txt")
    assert RunReconciliation.reconcile_in_flight("run-x", "SLICE-003", 3, path) == :rerun
  end
end
