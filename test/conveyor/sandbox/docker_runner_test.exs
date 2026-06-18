defmodule Conveyor.Sandbox.DockerRunnerTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Factory
  alias Conveyor.Factory.WorkspaceMaterialization
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.DockerRunner
  alias Conveyor.Sandbox.Materialized

  test "materialize exec destroy round-trips through docker command adapter" do
    repo = sample_git_repo!()

    fixture =
      create_artifact_run!(
        blob_root: temp_dir!("docker-runner-blobs"),
        base_commit: repo.base_commit,
        local_path: repo.project_path
      )

    run_spec = get_by_id!(Conveyor.Factory.RunSpec, fixture.run_attempt.run_spec_id)
    workspace_root = temp_dir!("docker-runner-workspaces")
    parent = self()

    cmd = fn
      "docker", ["create" | args], _opts ->
        send(parent, {:docker_create, args})
        {"container-123\n", 0}

      "docker", ["start", "container-123"], _opts ->
        send(parent, :docker_start)
        {"container-123\n", 0}

      "docker", ["exec" | args], _opts ->
        send(parent, {:docker_exec, args})
        {"ok\n", 0}

      "docker", ["rm", "-f", "container-123"], _opts ->
        send(parent, :docker_rm)
        {"container-123\n", 0}

      executable, args, opts ->
        System.cmd(executable, args, opts)
    end

    assert {:ok, %Materialized{} = materialized} =
             DockerRunner.materialize(run_spec,
               cmd: cmd,
               image_ref: "python:3.12-slim",
               workspace_root: workspace_root
             )

    assert materialized.container_id == "container-123"
    assert File.exists?(Path.join(materialized.path, "pyproject.toml"))
    assert File.exists?(Path.join(materialized.path, "tasks_service/main.py"))
    assert String.starts_with?(materialized.path, workspace_root)

    assert_received {:docker_create, create_args}
    assert Enum.member?(create_args, "python:3.12-slim")
    assert Enum.any?(create_args, &String.contains?(&1, "#{materialized.path}:/workspace:rw"))
    assert adjacent_args?(create_args, "--user", "65532:65532")
    assert adjacent_args?(create_args, "--network", "none")
    refute adjacent_args?(create_args, "--network", "host")
    assert adjacent_args?(create_args, "--security-opt", "no-new-privileges:true")
    assert adjacent_args?(create_args, "--cap-drop", "ALL")
    assert adjacent_args?(create_args, "--pids-limit", "256")
    assert adjacent_args?(create_args, "--cpus", "1.0")
    assert adjacent_args?(create_args, "--memory", "512m")
    assert "--read-only" in create_args
    assert "--privileged" not in create_args
    refute Enum.any?(create_args, &String.contains?(&1, "/var/run/docker.sock"))
    refute Enum.any?(create_args, &String.contains?(&1, System.user_home!()))
    assert_received :docker_start

    command = normalized_command(["python", "--version"], materialized.path)
    result = DockerRunner.exec(materialized, command, cmd: cmd)

    assert result.exit_code == 0
    assert result.stdout == "ok\n"
    assert_received {:docker_exec, exec_args}
    assert exec_args == ["-w", "/workspace", "container-123", "python", "--version"]

    assert :ok = DockerRunner.destroy(materialized, cmd: cmd)
    assert_received :docker_rm
    refute File.exists?(materialized.root_path)

    workspace = get_by_id!(WorkspaceMaterialization, materialized.workspace.id)
    assert workspace.cleanup_status == :deleted
    assert workspace.cleaned_at
    assert workspace.head_tree_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  defp normalized_command(argv, workspace_root) do
    command_spec = %CommandSpec{
      key: List.first(argv),
      argv: argv,
      cwd: ".",
      profile: :verify,
      network: :none,
      env_allowlist: [],
      timeout_ms: 120_000
    }

    NormalizedCommand.normalize!(command_spec, workspace_root: workspace_root)
  end

  defp sample_git_repo! do
    root = temp_dir!("docker-runner-source")
    project_path = Path.join(root, "samples/tasks_service")
    File.mkdir_p!(Path.join(project_path, "tasks_service"))
    File.write!(Path.join(project_path, "pyproject.toml"), "[project]\nname = \"sample\"\n")
    File.write!(Path.join(project_path, "tasks_service/main.py"), "print('sample')\n")

    System.cmd("git", ["init"], cd: root, stderr_to_stdout: true)

    System.cmd("git", ["config", "user.email", "test@example.com"],
      cd: root,
      stderr_to_stdout: true
    )

    System.cmd("git", ["config", "user.name", "Test User"], cd: root, stderr_to_stdout: true)
    System.cmd("git", ["add", "."], cd: root, stderr_to_stdout: true)
    System.cmd("git", ["commit", "-m", "sample"], cd: root, stderr_to_stdout: true)

    {base_commit, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true)

    %{root: root, project_path: project_path, base_commit: String.trim(base_commit)}
  end

  defp adjacent_args?(args, key, value) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(&(&1 == [key, value]))
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
