defmodule Mix.Tasks.Conveyor.Init do
  @moduledoc """
  Scaffolds a repository for Conveyor.

      mix conveyor.init SAMPLE_PROJECT_PATH
  """

  use Mix.Task

  @shortdoc "Scaffold .conveyor config, policies, prompts, artifacts, and AGENTS.md"

  @artifact_dirs [
    ".conveyor/runs",
    ".conveyor/blobs",
    ".conveyor/blobs/sha256"
  ]

  @template_files [
    {"config.toml", ".conveyor/config.toml"},
    {"policies/explore.toml", ".conveyor/policies/explore.toml"},
    {"policies/implement.toml", ".conveyor/policies/implement.toml"},
    {"policies/maintenance.toml", ".conveyor/policies/maintenance.toml"},
    {"policies/release.toml", ".conveyor/policies/release.toml"},
    {"policies/verify.toml", ".conveyor/policies/verify.toml"},
    {"prompts/implementation-prompt@1.md", ".conveyor/prompts/implementation-prompt@1.md"},
    {"prompts/reviewer@1.md", ".conveyor/prompts/reviewer@1.md"}
  ]

  @impl Mix.Task
  def run([project_path]) do
    project_path
    |> Path.expand()
    |> scaffold!()
  end

  def run(_args) do
    Mix.raise("usage: mix conveyor.init SAMPLE_PROJECT_PATH")
  end

  @spec scaffold!(Path.t()) :: :ok
  def scaffold!(project_path) do
    File.mkdir_p!(project_path)

    Enum.each(@artifact_dirs, fn dir ->
      create_dir!(project_path, dir)
    end)

    Enum.each(@template_files, fn {template, destination} ->
      copy_template!(project_path, template, destination)
    end)

    generate_agents!(project_path)

    :ok
  end

  defp create_dir!(project_path, relative_path) do
    path = Path.join(project_path, relative_path)
    File.mkdir_p!(path)
    Mix.shell().info([:green, "* created ", :reset, path])
  end

  defp copy_template!(project_path, template, destination) do
    destination_path = Path.join(project_path, destination)
    File.mkdir_p!(Path.dirname(destination_path))

    if File.exists?(destination_path) do
      Mix.shell().info([:yellow, "* exists  ", :reset, destination_path])
    else
      template
      |> template_path()
      |> File.cp!(destination_path)

      Mix.shell().info([:green, "* created ", :reset, destination_path])
    end
  end

  defp generate_agents!(project_path) do
    destination_path = Path.join(project_path, "AGENTS.md")

    if File.exists?(destination_path) do
      Mix.shell().info([:yellow, "* exists  ", :reset, destination_path])
    else
      path = Conveyor.AgentsMd.write!(project_path, overwrite?: false)
      Mix.shell().info([:green, "* created ", :reset, path])
    end
  end

  defp template_path(template) do
    case :code.priv_dir(:conveyor) do
      path when is_list(path) ->
        Path.join([List.to_string(path), "conveyor", "templates", template])

      {:error, _reason} ->
        Path.expand(Path.join(["priv", "conveyor", "templates", template]))
    end
  end
end
