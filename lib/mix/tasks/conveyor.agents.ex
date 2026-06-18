defmodule Mix.Tasks.Conveyor.Agents do
  @moduledoc """
  Generates AGENTS.md from `.conveyor/config.toml`.

      mix conveyor.agents SAMPLE_PROJECT_PATH
  """

  use Mix.Task

  @shortdoc "Generate AGENTS.md from Conveyor config"

  @impl Mix.Task
  def run([project_path]) do
    project_path = Path.expand(project_path)
    path = Conveyor.AgentsMd.write!(project_path, overwrite?: true)
    Mix.shell().info([:green, "* generated ", :reset, path])
  end

  def run(_args) do
    Mix.raise("usage: mix conveyor.agents SAMPLE_PROJECT_PATH")
  end
end
