defmodule Conveyor.Planning.RunReconciliation do
  @moduledoc """
  U5: exactly-once side-effect reconciliation for a resumed run.

  The slice side effect is an in-place accept-commit on the shared workspace
  (`git add -A; git commit -m "conveyor: accept <slice>"`; HEAD advances — there is no
  merge or push). Because the run ledger commits each slice outcome *after* the
  accept-commit (commit-first ordering), exactly one slice can be in the gap on a crash:
  its commit landed but its outcome event never recorded, so reconstruction sees it as the
  in-flight slice. Re-running it would produce a second accept-commit.

  This module detects that case from the live workspace: if HEAD is the in-flight slice's
  accept-commit, the side effect already landed — the caller records a recovered passed
  outcome and skips re-execution. Otherwise the slice is re-run from a clean base.
  """

  @doc """
  Decide whether the in-flight slice's accept-commit already landed in `workspace_path`.

  Returns `{:already_committed, outcome_payload}` (a synthesized passed outcome the caller
  records and reuses) or `:rerun`.
  """
  @spec reconcile_in_flight(String.t(), String.t(), pos_integer(), String.t()) ::
          {:already_committed, map()} | :rerun
  def reconcile_in_flight(run_id, slice_key, sequence, workspace_path)
      when is_binary(workspace_path) do
    if head_subject(workspace_path) == accept_subject(slice_key) do
      {:already_committed,
       %{
         "run_id" => run_id,
         "slice_id" => slice_key,
         "sequence" => sequence,
         "status" => "passed",
         "gate_result" => "recovered_commit",
         "run_attempt_outcome" => "accepted",
         "findings" => [],
         "head_commit" => head_commit(workspace_path),
         "head_tree" => head_tree_digest(workspace_path)
       }}
    else
      :rerun
    end
  end

  defp accept_subject(slice_key), do: "conveyor: accept #{slice_key}"

  defp head_subject(workspace_path), do: git(workspace_path, ["log", "-1", "--format=%s"])
  defp head_commit(workspace_path), do: git(workspace_path, ["rev-parse", "HEAD"])

  defp head_tree_digest(workspace_path),
    do: digest(git(workspace_path, ["rev-parse", "HEAD^{tree}"]))

  defp git(workspace_path, args) do
    case System.cmd("git", ["-C", workspace_path | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
