defmodule Conveyor.Sandbox.DockerRunner do
  @moduledoc """
  Docker-backed sandbox runner.
  """

  @behaviour Conveyor.Sandbox.Runner

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.WorkspaceMaterialization
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.DockerProfile
  alias Conveyor.Sandbox.Materialized
  alias Conveyor.Sandbox.Runner
  alias Conveyor.Sandbox.WorkspaceCleanup

  @workspace_mount "/workspace"

  @impl true
  def materialize(%RunSpec{} = run_spec, opts \\ []) do
    with {:ok, source} <- source_context(run_spec, opts),
         {:ok, paths} <- prepare_workspace_paths(run_spec, opts),
         {:ok, project_path} <- archive_checkout(source, run_spec.base_commit, paths, opts),
         {:ok, container_id} <- create_container(project_path, image_ref(run_spec, opts), opts),
         {:ok, workspace} <- record_workspace(run_spec, project_path, container_id, opts) do
      {:ok,
       %Materialized{
         workspace: workspace,
         path: project_path,
         root_path: paths.root_path,
         container_id: container_id,
         image_ref: image_ref(run_spec, opts)
       }}
    else
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def exec(%Materialized{} = materialized, %NormalizedCommand{} = command, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    args =
      ["exec", "-w", container_cwd(materialized, command)]
      |> Kernel.++(env_args(command.env_keys))
      |> Kernel.++([materialized.container_id, command.executable | command.argv])

    {output, exit_code} = cmd!("docker", args, opts)

    %Runner.Result{
      exit_code: exit_code,
      stdout: output,
      stderr: "",
      duration_ms: max(System.monotonic_time(:millisecond) - started, 0)
    }
  end

  @impl true
  def destroy(%Materialized{} = materialized, opts \\ []) do
    case WorkspaceCleanup.cleanup(materialized, opts) do
      {:ok, _workspace} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp source_context(run_spec, opts) do
    project = Keyword.get(opts, :project) || project_for_run_spec!(run_spec)
    repo_root = git_output!("rev-parse --show-toplevel", project.local_path, opts)
    project_prefix = git_output!("rev-parse --show-prefix", project.local_path, opts)

    {:ok,
     %{
       project: project,
       repo_root: repo_root,
       project_prefix: String.trim_trailing(project_prefix, "/")
     }}
  rescue
    error -> {:error, error}
  end

  defp prepare_workspace_paths(run_spec, opts) do
    workspace_root =
      opts
      |> Keyword.get(:workspace_root, Path.join(System.tmp_dir!(), "conveyor-workspaces"))
      |> Path.expand()

    root_path =
      workspace_root
      |> Path.join("#{run_spec.id}-#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.mkdir_p!(root_path)
    {:ok, %{workspace_root: workspace_root, root_path: root_path}}
  rescue
    error -> {:error, error}
  end

  defp archive_checkout(source, base_commit, paths, opts) do
    archive_path = Path.join(paths.root_path, "checkout.tar")

    archive_args = [
      "-C",
      source.repo_root,
      "archive",
      "--format=tar",
      "-o",
      archive_path,
      base_commit
    ]

    archive_args = archive_args ++ archive_pathspec(source.project_prefix)

    with {_output, 0} <- cmd!("git", archive_args, opts),
         {_output, 0} <- cmd!("tar", ["-xf", archive_path, "-C", paths.root_path], opts) do
      File.rm(archive_path)

      project_path =
        case source.project_prefix do
          "" -> paths.root_path
          prefix -> Path.join(paths.root_path, prefix)
        end

      {:ok, project_path}
    else
      {output, status} -> {:error, {:checkout_failed, status, output}}
    end
  end

  defp archive_pathspec(""), do: []
  defp archive_pathspec(prefix), do: ["--", prefix]

  defp create_container(project_path, image_ref, opts) do
    create_args =
      [
        "create",
        "--name",
        "conveyor-#{System.unique_integer([:positive])}",
        "--workdir",
        @workspace_mount
      ] ++
        DockerProfile.create_args(opts) ++
        workspace_mount_args(project_path) ++
        readonly_contract_mount_args(project_path) ++
        [image_ref, "sleep", "infinity"]

    with {container_id, 0} <- cmd!("docker", create_args, opts),
         {_output, 0} <- cmd!("docker", ["start", String.trim(container_id)], opts) do
      {:ok, String.trim(container_id)}
    else
      {output, status} -> {:error, {:container_create_failed, status, output}}
    end
  end

  defp workspace_mount_args(project_path),
    do: ["--volume", "#{project_path}:#{@workspace_mount}:rw"]

  defp readonly_contract_mount_args(project_path) do
    conveyor_path = Path.join(project_path, ".conveyor")

    if File.dir?(conveyor_path) do
      ["--volume", "#{conveyor_path}:#{@workspace_mount}/.conveyor:ro"]
    else
      []
    end
  end

  defp record_workspace(run_spec, project_path, container_id, opts) do
    workspace =
      Ash.create!(
        WorkspaceMaterialization,
        %{
          run_spec_id: run_spec.id,
          station_run_id: Keyword.get(opts, :station_run_id),
          purpose: Keyword.get(opts, :purpose, :implement),
          base_commit: run_spec.base_commit,
          path: project_path,
          container_id: container_id,
          mount_mode: Keyword.get(opts, :mount_mode, :read_write),
          head_tree_sha256: WorkspaceCleanup.tree_sha256(project_path),
          cleanup_policy: Keyword.get(opts, :cleanup_policy, :delete),
          cleanup_status: :pending
        },
        domain: Factory
      )

    {:ok, workspace}
  rescue
    error -> {:error, error}
  end

  defp container_cwd(materialized, command) do
    relative_path =
      command.cwd
      |> Path.expand()
      |> relative_to_workspace(materialized.path)

    if relative_path == "." do
      @workspace_mount
    else
      Path.join(@workspace_mount, relative_path)
    end
  end

  defp relative_to_workspace(path, workspace_path) do
    workspace_path = Path.expand(workspace_path)

    if path == workspace_path or not String.starts_with?(path, workspace_path <> "/") do
      "."
    else
      Path.relative_to(path, workspace_path)
    end
  end

  defp env_args(env_keys) do
    Enum.flat_map(env_keys, fn key -> ["--env", "#{key}=#{System.get_env(key) || ""}"] end)
  end

  defp image_ref(run_spec, opts), do: Keyword.get(opts, :image_ref, run_spec.container_image_ref)

  defp project_for_run_spec!(run_spec) do
    slice = get_by_id!(Slice, run_spec.slice_id)
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    get_by_id!(Project, plan.project_id)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp git_output!(command, path, opts) do
    args = ["-C", path | String.split(command, " ")]

    case cmd!("git", args, opts) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{command} failed with #{status}: #{output}"
    end
  end

  defp cmd!(executable, args, opts) do
    cmd_fun = Keyword.get(opts, :cmd, &System.cmd/3)
    cmd_fun.(executable, args, stderr_to_stdout: true)
  end
end
