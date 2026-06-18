defmodule Conveyor.AgentsMdTest do
  use ExUnit.Case, async: true

  alias Conveyor.AgentsMd
  alias Conveyor.Config

  @sample_config Path.expand("../../priv/conveyor/templates/config.toml", __DIR__)

  test "generates all required sections and configured commands" do
    config = Config.load!(@sample_config)
    content = AgentsMd.generate(config)

    for section <- AgentsMd.required_sections() do
      assert content =~ "# #{section}"
    end

    assert content =~ "- Test: `pytest` -> `pytest -q`"
    assert content =~ "- Lint: `format` -> `ruff format --check .`"
    assert content =~ "`pytest` [verify, required, network: none]: `pytest -q`"
    assert content =~ "`format` [verify, optional, network: none]: `ruff format --check .`"
    assert content =~ "CodeScent Context"
    assert content =~ "noop"
  end

  test "writes AGENTS.md from a project config" do
    project_path = temp_project_path()
    File.mkdir_p!(Path.join(project_path, ".conveyor"))
    File.cp!(@sample_config, Path.join(project_path, ".conveyor/config.toml"))

    path = AgentsMd.write!(project_path)

    assert path == Path.join(project_path, "AGENTS.md")
    assert File.read!(path) =~ "Configured command specs from `.conveyor/config.toml`"
  end

  defp temp_project_path do
    Path.join(System.tmp_dir!(), "conveyor-agents-md-#{System.unique_integer([:positive])}")
  end
end
