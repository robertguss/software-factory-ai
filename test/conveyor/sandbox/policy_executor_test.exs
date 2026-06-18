defmodule Conveyor.Sandbox.PolicyExecutorTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Factory
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.DockerRunner
  alias Conveyor.Sandbox.PolicyExecutor

  setup do
    repo = sample_git_repo!()

    fixture =
      create_artifact_run!(
        blob_root: temp_dir!("policy-executor-blobs"),
        base_commit: repo.base_commit,
        local_path: repo.project_path
      )

    run_spec = get_by_id!(RunSpec, fixture.run_attempt.run_spec_id)
    parent = self()

    cmd = fn
      "docker", ["create" | _args], _opts ->
        {"container-policy\n", 0}

      "docker", ["start", "container-policy"], _opts ->
        {"container-policy\n", 0}

      "docker", ["exec" | args], _opts ->
        send(parent, {:docker_exec, args})
        {"ok\n", 0}

      executable, args, opts ->
        System.cmd(executable, args, opts)
    end

    {:ok, materialized} =
      DockerRunner.materialize(run_spec,
        cmd: cmd,
        image_ref: "python:3.12-slim",
        workspace_root: temp_dir!("policy-executor-workspaces")
      )

    %{
      cmd: cmd,
      fixture: fixture,
      materialized: materialized,
      run_spec: run_spec,
      slice: get_by_id!(Slice, fixture.run_attempt.slice_id)
    }
  end

  test "allowed implement-profile command runs through DockerRunner", %{
    cmd: cmd,
    fixture: fixture,
    materialized: materialized
  } do
    command = normalized_command(["python", "--version"], materialized.path)
    policy = implement_policy(allowlist: ["python"])

    result =
      PolicyExecutor.execute!(materialized, command, policy,
        blob_root: temp_dir!("policy-executor-output"),
        docker_opts: [cmd: cmd],
        run_attempt_id: fixture.run_attempt.id,
        station_run_id: fixture.station_run.id
      )

    assert result.decision.status == :allowed
    assert result.invocation.status == :succeeded
    assert result.execution.stdout == "ok\n"

    assert_received {:docker_exec,
                     ["-w", "/workspace", "container-policy", "python", "--version"]}
  end

  test "forbidden implement-profile command creates incident and never reaches DockerRunner", %{
    cmd: cmd,
    fixture: fixture,
    materialized: materialized,
    slice: slice
  } do
    slice = Ash.update!(slice, %{state: :in_progress}, domain: Factory)
    run_attempt = Ash.update!(fixture.run_attempt, %{status: :running}, domain: Factory)

    command = normalized_command(["git", "reset", "--hard", "HEAD"], materialized.path)
    policy = implement_policy(allowlist: ["git"], denylist: ["git reset --hard"])

    result =
      PolicyExecutor.execute!(materialized, command, policy,
        blob_root: temp_dir!("policy-executor-blocked-output"),
        docker_opts: [cmd: cmd],
        run_attempt_id: run_attempt.id,
        station_run_id: fixture.station_run.id
      )

    refute_received {:docker_exec, _args}
    assert result.decision.status == :blocked
    assert result.violation.incident.category == "policy_violation"

    assert [incident] = Ash.read!(Incident, domain: Factory)
    assert incident.run_attempt_id == run_attempt.id

    stopped_attempt = get_by_id!(Conveyor.Factory.RunAttempt, run_attempt.id)
    assert stopped_attempt.status == :failed
    assert stopped_attempt.outcome == :policy_blocked

    blocked_slice = get_by_id!(Slice, slice.id)
    assert blocked_slice.state == :policy_blocked
  end

  defp normalized_command(argv, workspace_root) do
    command_spec = %CommandSpec{
      key: List.first(argv),
      argv: argv,
      cwd: ".",
      profile: :implement,
      network: :none,
      env_allowlist: [],
      timeout_ms: 120_000
    }

    NormalizedCommand.normalize!(command_spec, workspace_root: workspace_root)
  end

  defp implement_policy(opts) do
    %Policy{
      name: "implement",
      profile: :implement,
      allowlist: Keyword.get(opts, :allowlist, []),
      denylist: Keyword.get(opts, :denylist, []),
      env_policy: %{"allowlist" => []},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 1
    }
  end

  defp sample_git_repo! do
    root = temp_dir!("policy-executor-source")
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

    %{project_path: project_path, base_commit: String.trim(base_commit)}
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
