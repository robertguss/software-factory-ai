defmodule Conveyor.LockedTests do
  @moduledoc """
  Per-slice locked-test materialization.

  Independently-authored acceptance test bodies live committed under
  `<workspace>/.conveyor/locked-tests/<path>` — outside `tests/`, so pytest never
  collects them until they are staged. `stage!/2` copies a slice's locked test
  files to their real paths so the slice's implement/verify stations (and the
  calibration worktree, once committed into base) see exactly the tests that
  slice is contracted to satisfy.
  """

  @locked_root ".conveyor/locked-tests"

  @doc """
  Distinct, sorted test file paths for a list of `required_test_refs` (pytest node
  ids like `tests/test_fields.py::test_x`). The file path is everything before the
  first `::`.
  """
  @spec paths_for([String.t()]) :: [String.t()]
  def paths_for(refs) when is_list(refs) do
    refs
    |> Enum.map(&(&1 |> String.split("::", parts: 2) |> hd()))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Stage a slice's locked tests (from `required_test_refs`) into `tests/` and commit
  them, so the tests become part of the workspace HEAD (and thus the run's
  `base_commit`). This is what lets the agent diff cleanly against a base that
  already contains the locked tests, and lets the calibration worktree see them
  red at base. No-op (`:ok`) when the workspace has no `.conveyor/locked-tests`
  directory, when there are no refs, or when nothing changed.
  """
  @spec materialize!(String.t(), [String.t()], String.t()) :: :ok
  def materialize!(workspace_path, refs, label)
      when is_binary(workspace_path) and is_list(refs) and is_binary(label) do
    paths = paths_for(refs)

    if paths == [] or not File.dir?(Path.join(workspace_path, @locked_root)) do
      :ok
    else
      stage!(workspace_path, paths)
      commit!(workspace_path, paths, label)
    end
  end

  defp commit!(workspace_path, paths, label) do
    git!(workspace_path, ["add", "--" | paths])

    case git!(workspace_path, ["status", "--porcelain", "--" | paths]) do
      "" ->
        :ok

      _dirty ->
        git!(workspace_path, [
          "-c",
          "user.email=conveyor@example.invalid",
          "-c",
          "user.name=Conveyor",
          "commit",
          "-m",
          "conveyor: materialize locked tests for #{label}",
          "--" | paths
        ])

        :ok
    end
  end

  defp git!(workspace_path, args) do
    case System.cmd("git", ["-C", workspace_path | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end

  @doc """
  Copy each `path` from `<workspace>/.conveyor/locked-tests/<path>` to
  `<workspace>/<path>`, creating parent directories. Idempotent.
  """
  @spec stage!(String.t(), [String.t()]) :: :ok
  def stage!(workspace_path, paths) when is_binary(workspace_path) and is_list(paths) do
    Enum.each(paths, fn path ->
      source = Path.join([workspace_path, @locked_root, path])
      dest = Path.join(workspace_path, path)
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(source, dest)
    end)

    :ok
  end
end
