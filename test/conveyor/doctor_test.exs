defmodule Conveyor.DoctorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Doctor

  test "passes with warnings when only optional live-agent inputs are absent" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert result.status == :passed, inspect(result.findings)
    refute Enum.any?(result.findings, &(&1.severity == :failure))
    assert Enum.any?(result.findings, &(&1.check == :pi and &1.severity == :warning))
  end

  # --- mmxr.4: active-adapter + containment + policy-TOML prereqs -------------

  test "fails when the default (claude_code) agent backend CLI is absent" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :agent_backend_claude)
  end

  test "checks codex prereqs (not claude) when codex is the selected adapter" do
    project_path = scaffold_project!()

    # codex selected + present: no claude requirement, no agent-backend failure
    passing =
      Doctor.run(project_path,
        adapter: "codex",
        executable?: executable?(["docker", "git", "codex"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    refute Enum.any?(
             passing.findings,
             &(&1.check in [:agent_backend_claude, :agent_backend_codex])
           )

    # codex selected + absent: codex is the failing prereq
    failing =
      Doctor.run(project_path,
        adapter: "codex",
        executable?: executable?(["docker", "git"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(failing, :agent_backend_codex)
  end

  test "fails when a policy TOML file is malformed (a7kf: caught pre-flight, not at slice 1)" do
    project_path = scaffold_project!()
    policies_dir = Path.join(project_path, ".conveyor/policies")
    File.mkdir_p!(policies_dir)
    File.write!(Path.join(policies_dir, "broken.toml"), "this is = = not valid toml [[[")

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :policy_toml)
  end

  test "warns (does not fail) when the agent container image is not present locally" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        # docker_info returns nonzero for `docker image inspect` -> image absent
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert Enum.any?(result.findings, &(&1.check == :agent_image and &1.severity == :warning))
    refute Enum.any?(result.findings, &(&1.check == :agent_image and &1.severity == :failure))
  end

  test "fails when Docker is missing" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["git"]),
        docker_command: docker_info([]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :docker)

    assert Doctor.exit_code(result) ==
             Conveyor.CLI.ExitCodes.fetch!(:infrastructure_or_doctor_failure)
  end

  test "fails when Postgres is unreachable" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> {:error, :econnrefused} end
      )

    assert_failed(result, :postgres)

    assert Doctor.exit_code(result) ==
             Conveyor.CLI.ExitCodes.fetch!(:infrastructure_or_doctor_failure)
  end

  test "fails when policy profiles are missing" do
    project_path = scaffold_project!()
    File.rm!(Path.join(project_path, ".conveyor/policies/verify.toml"))

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :policy_profiles)

    assert Doctor.exit_code(result) ==
             Conveyor.CLI.ExitCodes.fetch!(:policy_or_secret_safety_violation)
  end

  test "fails when no verify command specs are configured" do
    project_path = scaffold_project!()
    config_path = Path.join(project_path, ".conveyor/config.toml")

    config_path
    |> File.read!()
    |> String.replace(~s(profile = "verify"), ~s(profile = "implement"))
    |> then(&File.write!(config_path, &1))

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :test_commands)

    assert Doctor.exit_code(result) ==
             Conveyor.CLI.ExitCodes.fetch!(:infrastructure_or_doctor_failure)
  end

  test "passes when sample repo is clean at the expected base ref" do
    {project_path, _sample_path, base_ref} = scaffold_project_with_sample_repo!()
    record_sample_repo!(project_path, base_ref)

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert result.status == :passed
    refute Enum.any?(result.findings, &(&1.check == :sample_repo))
  end

  test "fails when sample repo differs from the expected base ref" do
    {project_path, sample_path, base_ref} = scaffold_project_with_sample_repo!()
    record_sample_repo!(project_path, base_ref)
    File.write!(Path.join(sample_path, "app.py"), "print('changed')\n")

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=seccomp,profile=builtin", "name=rootless"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :sample_repo)

    assert Doctor.exit_code(result) ==
             Conveyor.CLI.ExitCodes.fetch!(:infrastructure_or_doctor_failure)
  end

  test "fails when required Docker sandbox constraints are unavailable" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git", "claude"]),
        docker_command: docker_info(["name=apparmor"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :sandbox_constraints)
  end

  # System.unique_integer resets per VM, so add a timestamp and wipe any leftover dir to
  # avoid landing on a prior run's populated git repo (a source of flaky git failures).
  defp doctor_project_path! do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-doctor-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    path
  end

  defp scaffold_project! do
    project_path = doctor_project_path!()

    capture_io(fn ->
      Mix.Tasks.Conveyor.Init.scaffold!(project_path)
    end)

    File.mkdir_p!(Path.join(project_path, ".git"))
    project_path
  end

  defp scaffold_project_with_sample_repo! do
    project_path = doctor_project_path!()

    sample_path = Path.join(project_path, "samples/tasks_service")

    capture_io(fn ->
      Mix.Tasks.Conveyor.Init.scaffold!(project_path)
    end)

    File.mkdir_p!(sample_path)
    File.write!(Path.join(sample_path, "app.py"), "print('baseline')\n")

    git!(project_path, ["init", "-b", "main"])
    git!(project_path, ["config", "user.email", "doctor-test@example.invalid"])
    git!(project_path, ["config", "user.name", "Doctor Test"])
    git!(project_path, ["add", "."])
    git!(project_path, ["commit", "-m", "sample base"])

    base_ref =
      project_path
      |> git!(["rev-parse", "HEAD"])
      |> String.trim()

    {project_path, sample_path, base_ref}
  end

  defp record_sample_repo!(project_path, base_ref) do
    config_path = Path.join(project_path, ".conveyor/config.toml")

    config_path
    |> File.read!()
    |> String.replace(
      ~s(quality_adapter = "noop"),
      ~s(quality_adapter = "noop"\nsample_repo_path = "samples/tasks_service"\nsample_base_ref = "#{base_ref}")
    )
    |> then(&File.write!(config_path, &1))
  end

  defp git!(path, args) do
    case System.cmd("git", ["-C", path | args], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end

  defp executable?(available) do
    available = MapSet.new(available)
    fn executable -> MapSet.member?(available, executable) end
  end

  defp docker_info(security_options) do
    fn
      "docker", ["info", "--format", "{{json .SecurityOptions}}"], _opts ->
        {inspect(security_options), 0}

      _executable, _args, _opts ->
        {"unexpected docker command", 1}
    end
  end

  defp assert_failed(result, check) do
    assert result.status == :failed
    assert finding = Enum.find(result.findings, &(&1.check == check and &1.severity == :failure))
    assert [%Conveyor.CLI.NextAction{command: "mix conveyor.doctor"} | _] = finding.next_actions
    assert Doctor.format(result) =~ "NextAction:"
    assert Doctor.format(result) =~ "rerun: mix conveyor.doctor"
  end
end
