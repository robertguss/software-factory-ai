defmodule Conveyor.Sandbox.WorkspaceCleanup do
  @moduledoc """
  Cleanup policy enforcement for materialized sandbox workspaces.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.WorkspaceMaterialization
  alias Conveyor.Sandbox.Materialized

  @spec cleanup(Materialized.t() | WorkspaceMaterialization.t(), keyword()) ::
          {:ok, WorkspaceMaterialization.t()} | {:error, term()}
  def cleanup(materialized_or_workspace, opts \\ [])

  def cleanup(%Materialized{} = materialized, opts) do
    cleanup(materialized.workspace, Keyword.put_new(opts, :root_path, materialized.root_path))
  end

  def cleanup(%WorkspaceMaterialization{} = workspace, opts) do
    remove_container(workspace.container_id, opts)

    cleanup_status =
      if preserve?(workspace.cleanup_policy, opts) do
        :preserved
      else
        delete_path(Keyword.get(opts, :root_path) || workspace.root_path || workspace.path)
      end

    updated =
      Ash.update!(
        workspace,
        %{cleanup_status: cleanup_status, cleaned_at: DateTime.utc_now(:microsecond)},
        domain: Factory
      )

    if cleanup_status == :failed, do: {:error, :workspace_cleanup_failed}, else: {:ok, updated}
  end

  @spec tree_sha256(Path.t()) :: String.t()
  def tree_sha256(path) do
    digest =
      path
      |> files()
      |> Enum.map_join("\n", fn file ->
        Path.relative_to(file, path) <> "\0" <> file_sha256(file)
      end)
      |> sha256()

    "sha256:" <> digest
  end

  defp preserve?(:preserve_always, _opts), do: true
  defp preserve?(:preserve_on_failure, opts), do: Keyword.get(opts, :failed?, false)
  defp preserve?(_policy, _opts), do: false

  defp delete_path(path) do
    File.rm_rf(path)
    if File.exists?(path), do: :failed, else: :deleted
  end

  defp remove_container(nil, _opts), do: :ok

  defp remove_container(container_id, opts) do
    opts
    |> Keyword.get(:cmd, &System.cmd/3)
    |> then(& &1.("docker", ["rm", "-f", container_id], stderr_to_stdout: true))

    :ok
  end

  defp files(path) do
    path
    |> walk_files()
    |> Enum.sort()
  end

  defp walk_files(path) do
    case File.ls(path) do
      {:ok, entries} ->
        Enum.flat_map(entries, &walk_entry(path, &1))

      {:error, _reason} ->
        []
    end
  end

  defp walk_entry(parent_path, entry) do
    child = Path.join(parent_path, entry)

    cond do
      File.dir?(child) -> walk_files(child)
      File.regular?(child) -> [child]
      true -> []
    end
  end

  defp file_sha256(path) do
    path
    |> File.read!()
    |> sha256()
  end

  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
