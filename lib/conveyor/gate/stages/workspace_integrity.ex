defmodule Conveyor.Gate.Stages.WorkspaceIntegrity do
  @moduledoc """
  Gate stage 1: verifies base/workspace integrity before semantic checks.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Gate.StageResult

  @impl true
  def run(context, _opts \\ []) do
    patch_set = value(context, :patch_set)
    run_spec = value(context, :run_spec)
    run_attempt = value(context, :run_attempt)
    head_tree_sha256 = value(context, :head_tree_sha256) || value(run_attempt, :head_tree_sha256)
    findings = findings(patch_set, run_spec, run_attempt, head_tree_sha256)

    %StageResult{
      key: "workspace_integrity",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(patch_set),
      input_digests: %{
        "base_commit" => value(patch_set, :base_commit),
        "head_tree_sha256" => head_tree_sha256
      },
      output_digest: head_tree_sha256
    }
  end

  defp findings(nil, _run_spec, _run_attempt, _head_tree_sha256) do
    [finding("missing_patch_set", "PatchSet is required for workspace integrity.")]
  end

  defp findings(patch_set, run_spec, run_attempt, head_tree_sha256) do
    []
    |> maybe_add(
      base_mismatch?(patch_set, run_spec, run_attempt),
      "base_commit_mismatch",
      "PatchSet base_commit does not match RunSpec/RunAttempt base_commit."
    )
    |> maybe_add(
      value(patch_set, :applies_cleanly) == false,
      "patch_apply_failed",
      "PatchSet does not apply cleanly to a fresh checkout."
    )
    |> maybe_add(
      value(patch_set, :touches_locked_paths) == true,
      "locked_path_touched",
      "PatchSet weakens or edits locked/protected paths."
    )
    |> maybe_add(
      is_nil(head_tree_sha256),
      "missing_head_tree_sha256",
      "Gate workspace head tree digest was not recorded."
    )
  end

  defp base_mismatch?(patch_set, run_spec, run_attempt) do
    patch_base = value(patch_set, :base_commit)

    Enum.any?([value(run_spec, :base_commit), value(run_attempt, :base_commit)], fn
      nil -> false
      expected -> expected != patch_base
    end)
  end

  defp evidence_refs(nil), do: []
  defp evidence_refs(patch_set), do: Enum.reject([value(patch_set, :patch_ref)], &is_nil/1)

  defp maybe_add(findings, true, category, message), do: [finding(category, message) | findings]
  defp maybe_add(findings, false, _category, _message), do: findings

  defp finding(category, message) do
    %{"category" => category, "severity" => "blocking", "message" => message}
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
