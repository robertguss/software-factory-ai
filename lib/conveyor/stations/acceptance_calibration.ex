defmodule Conveyor.Stations.AcceptanceCalibration do
  @moduledoc """
  Station wrapper for locked acceptance-test calibration.

  M4-A4: runs the locked acceptance commands at base FOR REAL in an ISOLATED detached
  git worktree at `base_commit` (never the live tree), so calibration is `:valid` only
  when those tests genuinely fail at base — proving they assert the *new* behavior.
  """

  use Conveyor.Station, station: "acceptance_calibration"

  alias Conveyor.AcceptanceCalibration
  alias Conveyor.Eval.{ToolchainRunner, Workspace}
  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec

  @impl Conveyor.Station
  def run(input, context) do
    calibration =
      context.run_attempt.run_spec_id
      |> run_spec!()
      |> calibrate(input)

    {:ok,
     %{
       "test_pack_calibration" => %{
         "id" => calibration.id,
         "status" => Atom.to_string(calibration.status),
         "expected_failures" => calibration.expected_failures
       }
     }}
  end

  defp calibrate(run_spec, input) do
    blob_root = Map.get(input, "blob_root", ".conveyor/blobs")

    case base_worktree(Map.get(input, "workspace_path"), Map.get(input, "base_commit")) do
      {:ok, workspace_path, worktree} ->
        try do
          AcceptanceCalibration.run!(run_spec,
            blob_root: blob_root,
            runner: ToolchainRunner.runner(worktree, Workspace.venv_opts())
          )
        after
          git(workspace_path, ["worktree", "remove", "--force", worktree])
        end

      :error ->
        AcceptanceCalibration.run!(run_spec, blob_root: blob_root)
    end
  end

  defp base_worktree(workspace_path, base_commit)
       when is_binary(workspace_path) and is_binary(base_commit) do
    worktree =
      Path.join(System.tmp_dir!(), "conveyor_calib_#{System.unique_integer([:positive])}")

    case git(workspace_path, ["worktree", "add", "--detach", worktree, base_commit]) do
      :ok -> {:ok, workspace_path, worktree}
      :error -> :error
    end
  end

  defp base_worktree(_workspace_path, _base_commit), do: :error

  defp git(workspace_path, args) do
    case System.cmd("git", ["-C", workspace_path | args], stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {_out, _status} -> :error
    end
  rescue
    _error -> :error
  end

  defp run_spec!(id) do
    RunSpec
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "RunSpec #{id} was not found"
  end
end
