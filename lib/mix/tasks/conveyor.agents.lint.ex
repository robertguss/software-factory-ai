defmodule Mix.Tasks.Conveyor.Agents.Lint do
  @moduledoc """
  Lints AGENTS.md against `.conveyor/config.toml` and policy files.

      mix conveyor.agents.lint SAMPLE_PROJECT_PATH
  """

  use Mix.Task

  @shortdoc "Lint AGENTS.md against Conveyor config"

  @impl Mix.Task
  def run([project_path]) do
    case Conveyor.AgentsMd.Linter.lint(Path.expand(project_path)) do
      {:ok, result} ->
        Mix.shell().info(Conveyor.AgentsMd.Linter.format(result))
        exit_fun().(if result.status == :passed, do: 0, else: 1)

      {:error, error} ->
        Mix.shell().error(Exception.message(error))
        exit_fun().(1)
    end
  end

  def run(_args) do
    Mix.raise("usage: mix conveyor.agents.lint SAMPLE_PROJECT_PATH")
  end

  defp exit_fun do
    Process.get(:conveyor_agents_lint_exit_fun, &System.halt/1)
  end
end
