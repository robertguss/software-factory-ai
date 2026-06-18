defmodule Conveyor.Gate.Stages.DiffScope do
  @moduledoc """
  Gate stage 2: checks PatchSet scope against the slice DiffPolicy.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Gate.StageResult

  @impl true
  def run(context, _opts \\ []) do
    patch_set = value(context, :patch_set)
    diff_policy = value(context, :diff_policy)
    findings = findings(patch_set, diff_policy)

    %StageResult{
      key: "diff_scope",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(patch_set),
      input_digests: %{"patch_sha256" => value(patch_set, :patch_sha256)}
    }
  end

  defp findings(nil, _diff_policy), do: [finding("missing_patch_set", "PatchSet is required.")]
  defp findings(_patch_set, nil), do: [finding("missing_diff_policy", "DiffPolicy is required.")]

  defp findings(patch_set, diff_policy) do
    files = value(patch_set, :changed_files) || []

    []
    |> check_allowed_paths(files, value(diff_policy, :allowed_path_globs) || [])
    |> check_protected_paths(files, value(diff_policy, :protected_path_globs) || [])
    |> check_max("max_files_changed", length(files), value(diff_policy, :max_files_changed))
    |> check_max(
      "max_lines_added",
      value(patch_set, :lines_added),
      value(diff_policy, :max_lines_added)
    )
    |> check_max(
      "max_lines_deleted",
      value(patch_set, :lines_deleted),
      value(diff_policy, :max_lines_deleted)
    )
    |> check_category(
      files,
      value(diff_policy, :dependency_changes_allowed),
      "dependency_change",
      &dependency_path?/1
    )
    |> check_category(
      files,
      value(diff_policy, :migrations_allowed),
      "migration_change",
      &migration_path?/1
    )
    |> check_category(
      files,
      value(diff_policy, :generated_files_allowed),
      "generated_file_change",
      &generated_path?/1
    )
    |> check_category(
      files,
      value(diff_policy, :public_api_changes_allowed),
      "public_api_change",
      &public_api_path?/1
    )
  end

  defp check_allowed_paths(findings, _files, []), do: findings

  defp check_allowed_paths(findings, files, allowed_globs) do
    unexpected = Enum.reject(files, &matches_any?(&1, allowed_globs))

    if unexpected == [] do
      findings
    else
      [
        finding("out_of_scope_path", "Changed files are outside allowed_path_globs.", unexpected)
        | findings
      ]
    end
  end

  defp check_protected_paths(findings, files, protected_globs) do
    protected = Enum.filter(files, &matches_any?(&1, protected_globs))

    if protected == [] do
      findings
    else
      [
        finding("protected_path_change", "Changed files match protected_path_globs.", protected)
        | findings
      ]
    end
  end

  defp check_max(findings, _category, _actual, nil), do: findings

  defp check_max(findings, category, actual, max) when is_integer(actual) and actual > max do
    [finding(category, "#{category} exceeded #{max}; got #{actual}.") | findings]
  end

  defp check_max(findings, _category, _actual, _max), do: findings

  defp check_category(findings, _files, true, _category, _predicate), do: findings

  defp check_category(findings, files, _allowed, category, predicate) do
    matches = Enum.filter(files, predicate)

    if matches == [] do
      findings
    else
      [finding(category, "#{category} is not allowed by DiffPolicy.", matches) | findings]
    end
  end

  defp dependency_path?(path) do
    path in [
      "mix.exs",
      "mix.lock",
      "package.json",
      "package-lock.json",
      "pnpm-lock.yaml",
      "yarn.lock"
    ]
  end

  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp generated_path?(path),
    do: String.contains?(path, "generated") or String.starts_with?(path, "priv/static/")

  defp public_api_path?(path),
    do: String.ends_with?(path, "_api.ex") or String.contains?(path, "/api/")

  defp matches_any?(_path, []), do: false
  defp matches_any?(path, globs), do: Enum.any?(globs, &glob_match?(path, &1))

  defp glob_match?(path, glob) do
    glob
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("^#{&1}$"))
    |> Regex.match?(path)
  end

  defp evidence_refs(nil), do: []
  defp evidence_refs(patch_set), do: Enum.reject([value(patch_set, :patch_ref)], &is_nil/1)

  defp finding(category, message, paths \\ []) do
    %{"category" => category, "severity" => "blocking", "message" => message, "paths" => paths}
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
