defmodule Conveyor.AgentRunner.PatchCapture do
  @moduledoc """
  Captures an agent-produced git diff as a Conveyor PatchSet.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.PatchSet

  @type workspace :: map() | struct()

  @spec capture!(workspace(), keyword()) :: PatchSet.t()
  def capture!(workspace, opts) do
    workspace_path = workspace_path!(workspace)
    base_commit = base_commit!(workspace, opts)
    run_attempt_id = Keyword.fetch!(opts, :run_attempt_id)
    agent_session_id = Keyword.get(opts, :agent_session_id)
    locked_paths = Keyword.get(opts, :locked_paths, [])
    blob_opts = Keyword.take(opts, [:blob_root])

    include_untracked!(workspace_path)
    diff = git_output!(workspace_path, ["diff", "--binary", "--find-renames", base_commit, "--"])
    blob = BlobStore.write!(diff, blob_opts)
    scope = scope(workspace_path, base_commit)
    changed_files = changed_files(scope)

    Ash.create!(
      PatchSet,
      %{
        run_attempt_id: run_attempt_id,
        agent_session_id: agent_session_id,
        base_commit: base_commit,
        patch_ref: blob.ref,
        patch_sha256: blob.sha256,
        changed_files: changed_files,
        added_files: files_by_status(scope.name_status, "A"),
        deleted_files: files_by_status(scope.name_status, "D"),
        renamed_files: renamed_files(scope.name_status),
        lines_added: scope.lines_added,
        lines_deleted: scope.lines_deleted,
        touches_locked_paths: touches_locked_paths?(changed_files, locked_paths),
        applies_cleanly: applies_cleanly?(workspace_path, base_commit, diff)
      },
      domain: Factory
    )
  end

  defp scope(workspace_path, base_commit) do
    name_status =
      workspace_path
      |> git!(["diff", "--name-status", "--find-renames", base_commit, "--"])
      |> parse_name_status()

    numstat =
      workspace_path
      |> git!(["diff", "--numstat", "--find-renames", base_commit, "--"])
      |> parse_numstat()

    %{
      name_status: name_status,
      lines_added: Enum.sum(Enum.map(numstat, & &1.added)),
      lines_deleted: Enum.sum(Enum.map(numstat, & &1.deleted))
    }
  end

  defp parse_name_status(""), do: []

  defp parse_name_status(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "\t") do
        ["R" <> _score = status, old_path, new_path] ->
          %{status: status, paths: [old_path, new_path]}

        [status, path] ->
          %{status: status, paths: [path]}
      end
    end)
  end

  defp parse_numstat(""), do: []

  defp parse_numstat(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [added, deleted | _paths] = String.split(line, "\t")
      %{added: parse_int(added), deleted: parse_int(deleted)}
    end)
  end

  defp parse_int("-"), do: 0
  defp parse_int(value), do: String.to_integer(value)

  defp changed_files(scope) do
    scope.name_status
    |> Enum.flat_map(fn
      %{status: "R" <> _, paths: [_old_path, new_path]} -> [new_path]
      %{paths: paths} -> paths
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp files_by_status(name_status, status) do
    name_status
    |> Enum.filter(&(&1.status == status))
    |> Enum.flat_map(& &1.paths)
    |> Enum.sort()
  end

  defp renamed_files(name_status) do
    name_status
    |> Enum.filter(&String.starts_with?(&1.status, "R"))
    |> Enum.map(fn %{paths: [_old_path, new_path]} -> new_path end)
    |> Enum.sort()
  end

  defp touches_locked_paths?(_changed_files, []), do: false

  defp touches_locked_paths?(changed_files, locked_paths) do
    Enum.any?(changed_files, fn file ->
      Enum.any?(locked_paths, &path_matches?(&1, file))
    end)
  end

  defp path_matches?(locked_path, file) do
    cond do
      String.contains?(locked_path, "*") ->
        locked_path
        |> glob_regex()
        |> Regex.match?(file)

      String.ends_with?(locked_path, "/") ->
        String.starts_with?(file, locked_path)

      true ->
        file == locked_path or String.starts_with?(file, locked_path <> "/")
    end
  end

  defp glob_regex(pattern) do
    pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")

    Regex.compile!("^#{pattern}$")
  end

  defp applies_cleanly?(_workspace_path, _base_commit, ""), do: true

  defp applies_cleanly?(workspace_path, base_commit, diff) do
    worktree_path =
      Path.join(System.tmp_dir!(), "conveyor-patch-check-#{System.unique_integer([:positive])}")

    patch_path =
      Path.join(System.tmp_dir!(), "conveyor-patch-#{System.unique_integer([:positive])}.patch")

    try do
      File.write!(patch_path, diff)
      git!(workspace_path, ["worktree", "add", "--detach", worktree_path, base_commit])

      case System.cmd("git", ["-C", worktree_path, "apply", "--check", patch_path],
             stderr_to_stdout: true
           ) do
        {_output, 0} -> true
        {_output, _status} -> false
      end
    after
      System.cmd("git", ["-C", workspace_path, "worktree", "remove", "--force", worktree_path],
        stderr_to_stdout: true
      )

      File.rm_rf!(worktree_path)
      File.rm_rf!(patch_path)
    end
  end

  defp workspace_path!(workspace) do
    workspace
    |> field(:path, :workspace_path)
    |> require_non_empty_string!(:workspace_path)
    |> Path.expand()
  end

  defp base_commit!(workspace, opts) do
    opts
    |> Keyword.get(:base_commit)
    |> Kernel.||(field(workspace, :base_commit))
    |> require_non_empty_string!(:base_commit)
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp field(struct, primary, fallback) do
    field(struct, primary) || field(struct, fallback)
  end

  defp require_non_empty_string!(value, _field) when is_binary(value) and value != "", do: value

  defp require_non_empty_string!(_value, field) do
    raise ArgumentError, "#{field} must be a non-empty string"
  end

  defp git!(workspace_path, args) do
    workspace_path
    |> git_output!(args)
    |> String.trim_trailing()
  end

  defp git_output!(workspace_path, args) do
    case System.cmd("git", ["-C", workspace_path | args], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> raise "git #{Enum.join(args, " ")} failed with #{status}: #{output}"
    end
  end

  defp include_untracked!(workspace_path) do
    git!(workspace_path, ["add", "--intent-to-add", "--", "."])
  end
end
