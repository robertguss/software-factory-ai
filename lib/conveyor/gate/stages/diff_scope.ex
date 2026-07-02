defmodule Conveyor.Gate.Stages.DiffScope do
  @moduledoc """
  Gate stage 2: checks PatchSet scope against the slice DiffPolicy.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Gate.StageResult

  # nyrl.1: shipped conservative always-allowed classes. Editing a package export barrel is the
  # normal mechanical consequence of in-scope work but is unpredictable at authoring time (8mnx).
  # A project profile extends this via DiffPolicy.always_allowed_path_classes. Protected paths and
  # locked tests are NEVER granted (precedence handled in split_out_of_scope/3).
  @shipped_always_allowed_classes [
    %{
      "name" => "package_barrels",
      "globs" => ["**/__init__.py", "**/index.ts", "**/index.js", "**/lib.rs", "**/mod.rs"]
    }
  ]

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
    allowed_globs = value(diff_policy, :allowed_path_globs) || []
    protected_globs = value(diff_policy, :protected_path_globs) || []

    # Files outside the declared allow-list, split into always-allowed class grants vs. true
    # violations. A protected path is never granted — protected beats allowed (nyrl.1 precedence).
    out_of_scope =
      if allowed_globs == [], do: [], else: Enum.reject(files, &matches_any?(&1, allowed_globs))

    {grants, violations} =
      split_out_of_scope(out_of_scope, always_allowed_classes(diff_policy), protected_globs)

    []
    |> check_out_of_scope(violations)
    |> check_protected_paths(files, protected_globs)
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
    |> prepend_grant_notes(grants)
  end

  defp check_out_of_scope(findings, []), do: findings

  defp check_out_of_scope(findings, violations) do
    [
      finding("out_of_scope_path", "Changed files are outside allowed_path_globs.", violations)
      | findings
    ]
  end

  # Split out-of-scope paths into always-allowed class grants vs. true violations. A protected
  # path is never granted (protected beats allowed); it stays a violation and protected_path_change
  # fires separately. Grants carry {path, class_name} for the gate-evidence note.
  defp split_out_of_scope(paths, classes, protected_globs) do
    {grants, violations} =
      Enum.reduce(paths, {[], []}, fn path, {grants, violations} ->
        class = not matches_any?(path, protected_globs) && class_name_for(path, classes)

        if class do
          {[{path, class} | grants], violations}
        else
          {grants, [path | violations]}
        end
      end)

    {Enum.reverse(grants), Enum.reverse(violations)}
  end

  defp always_allowed_classes(diff_policy),
    do:
      @shipped_always_allowed_classes ++ (value(diff_policy, :always_allowed_path_classes) || [])

  defp class_name_for(path, classes) do
    Enum.find_value(classes, fn class ->
      if matches_any?(path, class["globs"] || []), do: class["name"]
    end)
  end

  defp prepend_grant_notes(findings, grants), do: Enum.map(grants, &grant_note/1) ++ findings

  defp grant_note({path, class_name}) do
    %{
      "category" => "always_allowed_path",
      "severity" => "info",
      "message" => "#{path} allowed via class #{class_name}.",
      "paths" => [path]
    }
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
      "yarn.lock",
      "aube-lock.yaml"
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

  # Only blocking findings fail the stage; always-allowed grant notes are info-level evidence.
  defp status(findings) do
    if Enum.any?(findings, &(&1["severity"] == "blocking")), do: :failed, else: :passed
  end

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
