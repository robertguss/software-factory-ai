defmodule Conveyor.Eval.Workspace do
  @moduledoc """
  Workspace setup for execution-based evals (E1, B2): copy `samples/tasks_service`
  into a throwaway temp dir (never mutating the source tree) and apply a canary
  patch. Shared so the gauntlet and the golden thread set up identical workspaces.
  """

  @sample Path.expand("../../../samples/tasks_service", __DIR__)

  @doc "Absolute path to the committed sample project."
  @spec sample_path() :: String.t()
  def sample_path, do: @sample

  @doc "Opts for `ToolchainRunner` that reuse the sample's committed venv when present (offline)."
  @spec venv_opts() :: keyword()
  def venv_opts do
    bin = Path.join(@sample, ".venv/bin")
    if File.dir?(bin), do: [venv_bin: bin], else: []
  end

  @doc "Copy the sample into a fresh temp workspace (excluding venv/cache). Returns the path."
  @spec setup!() :: String.t()
  def setup! do
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

    dst
  end

  @doc """
  Apply a repo-root-relative canary patch (e.g.
  `samples/tasks_service/.conveyor/canary/mutants/x.patch`) into `ws`. The patch
  paths include `samples/tasks_service/`, so strip 3 leading components.
  """
  @spec apply_patch!(String.t(), String.t()) :: String.t()
  def apply_patch!(ws, patch_ref) do
    patch = Path.expand(patch_ref, File.cwd!())

    {_out, 0} =
      System.cmd("patch", ["-p3", "-f", "-d", ws, "-i", patch], stderr_to_stdout: true)

    ws
  end

  @doc "Remove a workspace."
  @spec cleanup(String.t()) :: :ok
  def cleanup(ws) do
    File.rm_rf(ws)
    :ok
  end
end
