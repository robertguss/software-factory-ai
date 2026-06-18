defmodule Conveyor.Sandbox.ReaperTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.WorkspaceMaterialization
  alias Conveyor.Sandbox.Reaper

  test "reaps pending delete-policy workspace and orphan container" do
    fixture = create_artifact_run!(blob_root: temp_dir!("reaper-blobs"))
    workspace_path = temp_dir!("reaper-delete")
    File.write!(Path.join(workspace_path, "file.txt"), "orphan\n")
    parent = self()

    workspace =
      workspace!(fixture,
        path: workspace_path,
        container_id: "container-delete",
        cleanup_policy: :delete
      )

    result = Reaper.reap!(cmd: docker_rm(parent))

    assert result.deleted == 1
    assert result.preserved == 0
    assert_received {:docker_rm, "container-delete"}
    refute File.exists?(workspace_path)

    updated = get_by_id!(WorkspaceMaterialization, workspace.id)
    assert updated.cleanup_status == :deleted
    assert updated.cleaned_at
  end

  test "preserves failed workspace when policy allows but still removes container" do
    fixture = create_artifact_run!(blob_root: temp_dir!("reaper-preserve-blobs"))
    workspace_path = temp_dir!("reaper-preserve")
    File.write!(Path.join(workspace_path, "file.txt"), "preserved\n")
    parent = self()

    workspace =
      workspace!(fixture,
        path: workspace_path,
        container_id: "container-preserve",
        cleanup_policy: :preserve_on_failure
      )

    result = Reaper.reap!(cmd: docker_rm(parent), failed?: true)

    assert result.deleted == 0
    assert result.preserved == 1
    assert_received {:docker_rm, "container-preserve"}
    assert File.exists?(workspace_path)

    updated = get_by_id!(WorkspaceMaterialization, workspace.id)
    assert updated.cleanup_status == :preserved
    assert updated.cleaned_at
  end

  defp workspace!(fixture, attrs) do
    Ash.create!(
      WorkspaceMaterialization,
      %{
        run_spec_id: fixture.run_attempt.run_spec_id,
        station_run_id: fixture.station_run.id,
        purpose: :implement,
        base_commit: fixture.run_attempt.base_commit,
        path: Keyword.fetch!(attrs, :path),
        container_id: Keyword.fetch!(attrs, :container_id),
        mount_mode: :read_write,
        cleanup_policy: Keyword.fetch!(attrs, :cleanup_policy),
        cleanup_status: :pending
      },
      domain: Factory
    )
  end

  defp docker_rm(parent) do
    fn
      "docker", ["rm", "-f", container_id], _opts ->
        send(parent, {:docker_rm, container_id})
        {container_id <> "\n", 0}

      _executable, _args, _opts ->
        {"unexpected command", 1}
    end
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
