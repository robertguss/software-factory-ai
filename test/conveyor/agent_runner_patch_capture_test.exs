defmodule Conveyor.AgentRunnerPatchCaptureTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.AgentRunner.PatchCapture
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.PatchSet

  test "captures PatchSet scope, locked path touches, and clean apply status" do
    workspace_path = git_workspace!("agent-runner-patch-capture")
    base_commit = git!(workspace_path, ["rev-parse", "HEAD"])
    blob_root = temp_dir!("patch-capture-blobs")
    fixture = create_artifact_run!(blob_root: blob_root, base_commit: base_commit)

    File.write!(Path.join(workspace_path, "sample.txt"), "changed\n")
    File.write!(Path.join(workspace_path, "added.txt"), "added\n")
    File.rm!(Path.join(workspace_path, "remove.txt"))
    File.rename!(Path.join(workspace_path, "old.txt"), Path.join(workspace_path, "new.txt"))
    File.write!(Path.join(workspace_path, "locked/config.exs"), "locked changed\n")

    patch_set =
      PatchCapture.capture!(%{path: workspace_path, base_commit: base_commit},
        run_attempt_id: fixture.run_attempt.id,
        blob_root: blob_root,
        locked_paths: ["locked/**"]
      )

    assert patch_set.base_commit == base_commit
    assert patch_set.patch_ref =~ ~r(^sha256/[0-9a-f]{2}/[0-9a-f]{64}$)
    assert patch_set.patch_sha256 =~ ~r(^[0-9a-f]{64}$)

    assert patch_set.changed_files == [
             "added.txt",
             "locked/config.exs",
             "new.txt",
             "remove.txt",
             "sample.txt"
           ]

    assert patch_set.added_files == ["added.txt"]
    assert patch_set.deleted_files == ["remove.txt"]
    assert patch_set.renamed_files == ["new.txt"]
    assert patch_set.lines_added == 3
    assert patch_set.lines_deleted == 3
    assert patch_set.touches_locked_paths
    assert patch_set.applies_cleanly

    patch = BlobStore.read!(patch_set.patch_ref, blob_root: blob_root)
    assert patch =~ "diff --git a/sample.txt b/sample.txt"
    assert patch =~ "diff --git a/old.txt b/new.txt"
    assert patch =~ "+locked changed"

    assert [stored] = Ash.read!(PatchSet, domain: Factory)
    assert stored.id == patch_set.id
  end

  defp git_workspace!(label) do
    path = temp_dir!(label)
    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "conveyor@example.test"])
    git!(path, ["config", "user.name", "Conveyor Test"])

    File.write!(Path.join(path, "sample.txt"), "original\n")
    File.write!(Path.join(path, "remove.txt"), "remove me\n")
    File.write!(Path.join(path, "old.txt"), "renamed\n")
    File.mkdir_p!(Path.join(path, "locked"))
    File.write!(Path.join(path, "locked/config.exs"), "locked original\n")

    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "base"])
    path
  end

  defp git!(path, args) do
    {output, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(output)
  end
end
