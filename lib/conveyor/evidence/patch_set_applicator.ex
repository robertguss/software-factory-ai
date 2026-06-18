defmodule Conveyor.Evidence.PatchSetApplicator do
  @moduledoc """
  Applies a recorded PatchSet to a clean gate workspace.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.WorkspaceMaterialization
  alias Conveyor.Sandbox.WorkspaceCleanup

  @type result :: {:ok, WorkspaceMaterialization.t()} | {:error, map()}

  @spec apply_patch_set(PatchSet.t() | String.t(), keyword()) :: result()
  def apply_patch_set(patch_set_or_id, opts \\ [])

  def apply_patch_set(patch_set_id, opts) when is_binary(patch_set_id) do
    patch_set_id
    |> get_by_id!(PatchSet)
    |> apply_patch_set(opts)
  end

  def apply_patch_set(%PatchSet{} = patch_set, opts) do
    run_attempt = get_by_id!(patch_set.run_attempt_id, RunAttempt)
    run_spec = get_by_id!(run_attempt.run_spec_id, RunSpec)

    with :ok <- validate_base(patch_set, run_attempt),
         {:ok, project_path} <- materialize_clean_workspace(run_spec, opts),
         :ok <- apply_patch(project_path, patch_set, opts) do
      head_tree_sha256 = WorkspaceCleanup.tree_sha256(project_path)

      workspace =
        Ash.create!(
          WorkspaceMaterialization,
          %{
            run_spec_id: run_spec.id,
            station_run_id: Keyword.get(opts, :station_run_id),
            purpose: :gate,
            base_commit: patch_set.base_commit,
            applied_patch_sha256: patch_set.patch_sha256,
            path: project_path,
            mount_mode: :read_write,
            head_tree_sha256: head_tree_sha256,
            cleanup_policy: Keyword.get(opts, :cleanup_policy, :preserve_on_failure),
            cleanup_status: :pending
          },
          domain: Factory
        )

      Ash.update!(
        run_attempt,
        %{patch_set_id: patch_set.id, head_tree_sha256: head_tree_sha256},
        domain: Factory
      )

      {:ok, workspace}
    end
  rescue
    error -> {:error, finding("gate_workspace_error", Exception.message(error), %{})}
  end

  defp validate_base(patch_set, run_attempt) do
    if patch_set.base_commit == run_attempt.base_commit do
      :ok
    else
      {:error,
       finding("unexpected_base", "PatchSet base_commit does not match RunAttempt base_commit", %{
         "patch_set_base_commit" => patch_set.base_commit,
         "run_attempt_base_commit" => run_attempt.base_commit
       })}
    end
  end

  defp materialize_clean_workspace(run_spec, opts) do
    project = project_for_run_spec!(run_spec)
    repo_root = git!(project.local_path, ["rev-parse", "--show-toplevel"])

    project_prefix =
      project.local_path |> git!(["rev-parse", "--show-prefix"]) |> String.trim_trailing("/")

    workspace_root =
      opts
      |> Keyword.get(:workspace_root, Path.join(System.tmp_dir!(), "conveyor-gate-workspaces"))
      |> Path.expand()

    root_path =
      workspace_root
      |> Path.join("#{run_spec.id}-#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.mkdir_p!(root_path)
    archive_path = Path.join(root_path, "checkout.tar")
    archive_args = ["archive", "--format=tar", "-o", archive_path, run_spec.base_commit]
    archive_args = archive_args ++ archive_pathspec(project_prefix)

    with :ok <- cmd_ok("git", ["-C", repo_root | archive_args]),
         :ok <- cmd_ok("tar", ["-xf", archive_path, "-C", root_path]) do
      File.rm(archive_path)

      project_path =
        case project_prefix do
          "" -> root_path
          prefix -> Path.join(root_path, prefix)
        end

      {:ok, project_path}
    else
      {:error, reason} ->
        {:error,
         finding("clean_checkout_failed", "Could not materialize clean gate workspace", reason)}
    end
  end

  defp apply_patch(project_path, patch_set, opts) do
    patch = BlobStore.read!(patch_set.patch_ref, Keyword.take(opts, [:blob_root]))

    patch_path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-gate-patch-#{System.unique_integer([:positive])}.patch"
      )

    try do
      File.write!(patch_path, patch)

      case System.cmd("git", ["-C", project_path, "apply", patch_path], stderr_to_stdout: true) do
        {_output, 0} ->
          :ok

        {output, status} ->
          {:error,
           finding("patch_apply_failed", "PatchSet did not apply cleanly to gate workspace", %{
             "exit_status" => status,
             "output" => output
           })}
      end
    after
      File.rm_rf!(patch_path)
    end
  end

  defp project_for_run_spec!(run_spec) do
    slice = get_by_id!(run_spec.slice_id, Slice)
    epic = get_by_id!(slice.epic_id, Epic)
    plan = get_by_id!(epic.plan_id, Plan)
    get_by_id!(plan.project_id, Project)
  end

  defp archive_pathspec(""), do: []
  defp archive_pathspec(prefix), do: ["--", prefix]

  defp get_by_id!(id, resource) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp git!(path, args) do
    case System.cmd("git", ["-C", path | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed with #{status}: #{output}"
    end
  end

  defp cmd_ok(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, %{"exit_status" => status, "output" => output}}
    end
  end

  defp finding(category, message, details) do
    %{
      "severity" => "blocking",
      "category" => category,
      "message" => message,
      "details" => details
    }
  end
end
