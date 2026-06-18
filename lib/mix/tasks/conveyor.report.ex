defmodule Mix.Tasks.Conveyor.Report do
  @moduledoc """
  Regenerates the static artifact report for a run attempt.

      mix conveyor.report RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]
  """

  use Mix.Task

  alias Conveyor.Replay

  @shortdoc "Regenerate a run attempt artifact report"

  @impl Mix.Task
  def run([run_attempt_id | args]) do
    Mix.Task.run("app.start")

    opts = parse_opts!(args)

    run_attempt_id
    |> Replay.project_run!(opts)
    |> format_report()
    |> Jason.encode!()
    |> Mix.shell().info()
  end

  def run(_args) do
    Mix.raise(usage())
  end

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [blob_root: :string, projection_root: :string]
      )

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    opts
  end

  defp format_report(result) do
    manifest_path = Path.join(result.projection_path, "manifest.json")
    entries = manifest_entries(manifest_path)

    %{
      "run_attempt_id" => result.run_attempt_id,
      "projection_path" => result.projection_path,
      "manifest_path" => manifest_path,
      "artifact_count" => result.artifact_count,
      "manifest_sha256" => result.manifest_sha256,
      "bundle_root_sha256" => result.bundle_root_sha256,
      "entry_paths" => Enum.map(entries, &Path.join(result.projection_path, &1["path"]))
    }
  end

  defp manifest_entries(manifest_path) do
    manifest_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("entries")
  end

  defp usage do
    """
    usage:
      mix conveyor.report RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]
    """
    |> String.trim()
  end
end
