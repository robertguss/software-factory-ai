defmodule Conveyor.DoctorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Doctor

  test "passes with warnings when only optional live-agent inputs are absent" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["docker", "git"]),
        postgres_check: fn _config -> :ok end
      )

    assert result.status == :passed, inspect(result.findings)
    refute Enum.any?(result.findings, &(&1.severity == :failure))
    assert Enum.any?(result.findings, &(&1.check == :pi and &1.severity == :warning))
  end

  test "fails when Docker is missing" do
    project_path = scaffold_project!()

    result =
      Doctor.run(project_path,
        executable?: executable?(["git"]),
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
        executable?: executable?(["docker", "git"]),
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
        executable?: executable?(["docker", "git"]),
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
        executable?: executable?(["docker", "git"]),
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
        executable?: executable?(["docker", "git"]),
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
        executable?: executable?(["docker", "git"]),
        postgres_check: fn _config -> :ok end
      )

    assert_failed(result, :sample_repo)

    assert Doctor.exit_code(result) ==
             Conveyor.CLI.ExitCodes.fetch!(:infrastructure_or_doctor_failure)
  end

  defp scaffold_project! do
    project_path =
      Path.join(System.tmp_dir!(), "conveyor-doctor-#{System.unique_integer([:positive])}")

    capture_io(fn ->
      Mix.Tasks.Conveyor.Init.scaffold!(project_path)
    end)

    File.mkdir_p!(Path.join(project_path, ".git"))
    project_path
  end

  defp scaffold_project_with_sample_repo! do
    project_path =
      Path.join(System.tmp_dir!(), "conveyor-doctor-#{System.unique_integer([:positive])}")

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

  defp assert_failed(result, check) do
    assert result.status == :failed
    assert finding = Enum.find(result.findings, &(&1.check == check and &1.severity == :failure))
    assert [%Conveyor.CLI.NextAction{command: "mix conveyor.doctor"} | _] = finding.next_actions
    assert Doctor.format(result) =~ "NextAction:"
    assert Doctor.format(result) =~ "rerun: mix conveyor.doctor"
  end
end
