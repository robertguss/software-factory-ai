defmodule Conveyor.ConfigTest do
  use ExUnit.Case, async: true

  alias Conveyor.Config
  alias Conveyor.Config.CommandSpec
  alias Conveyor.Config.ProjectConfig
  alias Conveyor.Config.ValidationError

  @sample_config Path.expand("../../priv/conveyor/templates/config.toml", __DIR__)

  test "loads and validates the sample project config" do
    assert {:ok, %ProjectConfig{} = config} = Config.load(@sample_config)

    assert config.name == "sample_tasks"
    assert config.repo_path == "."
    assert config.default_branch == "main"
    assert config.dev_branch == "conveyor/dev"
    assert config.default_autonomy_level == :L1
    assert config.policies_dir == ".conveyor/policies"
    assert config.prompts_dir == ".conveyor/prompts"
    assert config.runs_dir == ".conveyor/runs"
    assert config.blobs_dir == ".conveyor/blobs"
    assert config.quality_adapter == "noop"
    assert config.sample_repo_path == nil
    assert config.sample_base_ref == nil

    assert [
             %CommandSpec{
               key: "pytest",
               argv: ["pytest", "-q"],
               profile: :verify,
               required: true,
               network: :none,
               result_format: :junit
             },
             %CommandSpec{key: "format", required: false, result_format: :stdout}
           ] = config.command_specs
  end

  test "reports missing required keys clearly" do
    path =
      write_config!("""
      [project]
      repo_path = "."
      default_branch = "main"
      default_autonomy_level = "L1"
      policies_dir = ".conveyor/policies"
      prompts_dir = ".conveyor/prompts"
      runs_dir = ".conveyor/runs"
      blobs_dir = ".conveyor/blobs"
      quality_adapter = "noop"

      [[project.command_specs]]
      key = "pytest"
      argv = ["pytest", "-q"]
      profile = "verify"
      """)

    assert {:error,
            %ValidationError{
              reason: :missing_required_key,
              message: "missing required config key project.name",
              path: ["project", "name"]
            }} = Config.load(path)
  end

  test "reports invalid command spec values with a precise path" do
    path =
      write_config!("""
      [project]
      name = "sample_tasks"
      repo_path = "."
      default_branch = "main"
      default_autonomy_level = "L1"
      policies_dir = ".conveyor/policies"
      prompts_dir = ".conveyor/prompts"
      runs_dir = ".conveyor/runs"
      blobs_dir = ".conveyor/blobs"
      quality_adapter = "noop"

      [[project.command_specs]]
      key = "pytest"
      argv = ["pytest", "-q"]
      profile = "danger"
      """)

    assert {:error,
            %ValidationError{
              reason: :invalid_value,
              message:
                "invalid config key project.command_specs.0.profile: expected one of explore, implement, verify, release, maintenance",
              path: ["project", "command_specs", "0", "profile"]
            }} = Config.load(path)
  end

  test "loads optional sample repo metadata" do
    path =
      write_config!("""
      [project]
      name = "sample_tasks"
      repo_path = "."
      default_branch = "main"
      default_autonomy_level = "L1"
      policies_dir = ".conveyor/policies"
      prompts_dir = ".conveyor/prompts"
      runs_dir = ".conveyor/runs"
      blobs_dir = ".conveyor/blobs"
      quality_adapter = "noop"
      sample_repo_path = "samples/tasks_service"
      sample_base_ref = "60426b147bd2b752dc03710f75e740f81bb5e3ee"

      [[project.command_specs]]
      key = "pytest"
      argv = ["pytest", "-q"]
      profile = "verify"
      """)

    assert {:ok, %ProjectConfig{} = config} = Config.load(path)
    assert config.sample_repo_path == "samples/tasks_service"
    assert config.sample_base_ref == "60426b147bd2b752dc03710f75e740f81bb5e3ee"
  end

  test "builds the default project config path" do
    assert Config.default_path("/repo") == "/repo/.conveyor/config.toml"
  end

  defp write_config!(content) do
    path =
      Path.join(System.tmp_dir!(), "conveyor-config-#{System.unique_integer([:positive])}.toml")

    File.write!(path, content)
    path
  end
end
