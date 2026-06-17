defmodule Mix.Tasks.ConveyorInitTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "scaffolds the full .conveyor tree and starter AGENTS.md" do
    project_path = temp_project_path()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.init")
        Mix.Task.run("conveyor.init", [project_path])
      end)

    assert output =~ ".conveyor/config.toml"
    assert File.regular?(Path.join(project_path, ".conveyor/config.toml"))
    assert File.regular?(Path.join(project_path, ".conveyor/policies/implement.toml"))
    assert File.regular?(Path.join(project_path, ".conveyor/policies/verify.toml"))
    assert File.regular?(Path.join(project_path, ".conveyor/prompts/implementation-prompt@1.md"))
    assert File.regular?(Path.join(project_path, ".conveyor/prompts/reviewer@1.md"))
    assert File.dir?(Path.join(project_path, ".conveyor/runs"))
    assert File.dir?(Path.join(project_path, ".conveyor/blobs"))
    assert File.dir?(Path.join(project_path, ".conveyor/blobs/sha256"))
    assert File.regular?(Path.join(project_path, "AGENTS.md"))

    assert {:ok, _config} = Conveyor.Config.load(Path.join(project_path, ".conveyor/config.toml"))
  end

  test "does not overwrite existing files" do
    project_path = temp_project_path()
    File.mkdir_p!(project_path)
    agents_path = Path.join(project_path, "AGENTS.md")
    File.write!(agents_path, "custom instructions")

    capture_io(fn ->
      Mix.Task.reenable("conveyor.init")
      Mix.Task.run("conveyor.init", [project_path])
    end)

    assert File.read!(agents_path) == "custom instructions"
  end

  defp temp_project_path do
    Path.join(System.tmp_dir!(), "conveyor-init-#{System.unique_integer([:positive])}")
  end
end
