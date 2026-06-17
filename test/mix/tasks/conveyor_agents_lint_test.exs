defmodule Mix.Tasks.ConveyorAgentsLintTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Conveyor.AgentsMd
  alias Conveyor.Config

  @sample_config Path.expand("../../../priv/conveyor/templates/config.toml", __DIR__)

  test "prints pass result and exits zero for compliant AGENTS.md" do
    project_path = temp_project_path()
    scaffold_project!(project_path)

    config = Config.load!(Path.join(project_path, ".conveyor/config.toml"))
    File.write!(Path.join(project_path, "AGENTS.md"), AgentsMd.generate(config))

    Process.put(:conveyor_agents_lint_exit_fun, fn code -> send(self(), {:exit_code, code}) end)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.agents.lint")
        Mix.Task.run("conveyor.agents.lint", [project_path])
      end)

    assert output =~ "AGENTS.md lint passed"
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_agents_lint_exit_fun)
  end

  test "prints findings and exits nonzero for invalid AGENTS.md" do
    project_path = temp_project_path()
    scaffold_project!(project_path)
    File.write!(Path.join(project_path, "AGENTS.md"), "# Project Overview\n")

    Process.put(:conveyor_agents_lint_exit_fun, fn code -> send(self(), {:exit_code, code}) end)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.agents.lint")
        Mix.Task.run("conveyor.agents.lint", [project_path])
      end)

    assert output =~ "AGENTS.md lint failed"
    assert output =~ "missing_section"
    assert_received {:exit_code, 1}
  after
    Process.delete(:conveyor_agents_lint_exit_fun)
  end

  defp scaffold_project!(project_path) do
    File.mkdir_p!(Path.join(project_path, ".conveyor/policies"))
    File.cp!(@sample_config, Path.join(project_path, ".conveyor/config.toml"))

    File.cp!(
      "priv/conveyor/templates/policies/implement.toml",
      Path.join(project_path, ".conveyor/policies/implement.toml")
    )

    File.cp!(
      "priv/conveyor/templates/policies/verify.toml",
      Path.join(project_path, ".conveyor/policies/verify.toml")
    )
  end

  defp temp_project_path do
    Path.join(
      System.tmp_dir!(),
      "conveyor-agents-lint-task-#{System.unique_integer([:positive])}"
    )
  end
end
