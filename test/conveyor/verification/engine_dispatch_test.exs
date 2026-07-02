defmodule Conveyor.Verification.EngineDispatchTest do
  @moduledoc "tt6v.2: language -> engine dispatch + toolchain profile default identity."
  use Conveyor.DataCase, async: false

  alias Conveyor.Doctor
  alias Conveyor.Factory
  alias Conveyor.Factory.ToolchainProfile
  alias Conveyor.Verification.EngineDispatch

  describe "engine_for/1" do
    test "python (and the absent/default) use the pytest specialization" do
      assert EngineDispatch.engine_for("python") == :pytest
      assert EngineDispatch.engine_for(:python) == :pytest
      assert EngineDispatch.engine_for(nil) == :pytest
    end

    test "every other language uses the generic command seam" do
      assert EngineDispatch.engine_for("elixir") == :command
      assert EngineDispatch.engine_for("javascript") == :command
      assert EngineDispatch.engine_for("rust") == :command
    end
  end

  test "a profile created without a language defaults to python (migration parity)" do
    profile =
      Ash.create!(
        ToolchainProfile,
        %{key: "unspecified", image_ref: "img:1", image_digest: "sha256:abc"},
        domain: Factory
      )

    assert profile.language == "python"
    assert profile.env_prep == "python_venv"
    assert profile.default_result_format == "junit"
    assert EngineDispatch.engine_for(profile.language) == :pytest
  end

  describe "conveyor.doctor toolchain profile image check (tt6v.2)" do
    setup do
      Ash.create!(
        ToolchainProfile,
        %{
          key: "elixir-runner",
          language: "elixir",
          image_ref: "ghcr.io/conveyor/elixir-runner:2026-07-02",
          image_digest: "sha256:elixir"
        },
        domain: Factory
      )

      %{project_path: System.tmp_dir!()}
    end

    test "warns with an actionable pull command when the profile image is absent locally", %{
      project_path: project_path
    } do
      result = Doctor.run(project_path, doctor_opts(image_present?: false))

      assert finding = Enum.find(result.findings, &(&1.check == :toolchain_profile_image))
      assert finding.severity == :warning
      assert finding.message =~ "elixir-runner"
      assert finding.message =~ "ghcr.io/conveyor/elixir-runner:2026-07-02"

      assert [%{command: "docker pull ghcr.io/conveyor/elixir-runner:2026-07-02"}] =
               finding.next_actions
    end

    test "no finding when the profile image is present locally", %{project_path: project_path} do
      result = Doctor.run(project_path, doctor_opts(image_present?: true))
      refute Enum.any?(result.findings, &(&1.check == :toolchain_profile_image))
    end
  end

  defp doctor_opts(image_present?: present?) do
    [
      executable?: fn _cmd -> true end,
      postgres_check: fn _config -> :ok end,
      docker_command: fn
        "docker", ["image", "inspect", _ref], _opts ->
          if present?, do: {"[]", 0}, else: {"No such image", 1}

        "docker", _args, _opts ->
          {"[\"name=seccomp,profile=builtin\",\"name=rootless\"]", 0}
      end
    ]
  end
end
