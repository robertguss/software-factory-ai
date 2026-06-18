defmodule Mix.Tasks.ConveyorAgentsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @sample_config Path.expand("../../../priv/conveyor/templates/config.toml", __DIR__)

  test "generates AGENTS.md for a Conveyor project" do
    project_path = temp_project_path()
    File.mkdir_p!(Path.join(project_path, ".conveyor"))
    File.cp!(@sample_config, Path.join(project_path, ".conveyor/config.toml"))

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.agents")
        Mix.Task.run("conveyor.agents", [project_path])
      end)

    assert output =~ "AGENTS.md"
    assert File.read!(Path.join(project_path, "AGENTS.md")) =~ "`pytest` [verify, required"
  end

  defp temp_project_path do
    Path.join(System.tmp_dir!(), "conveyor-agents-task-#{System.unique_integer([:positive])}")
  end
end
