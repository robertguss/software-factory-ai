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

    assert result.status == :passed
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

  defp scaffold_project! do
    project_path =
      Path.join(System.tmp_dir!(), "conveyor-doctor-#{System.unique_integer([:positive])}")

    capture_io(fn ->
      Mix.Tasks.Conveyor.Init.scaffold!(project_path)
    end)

    File.mkdir_p!(Path.join(project_path, ".git"))
    project_path
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
