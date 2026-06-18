defmodule Conveyor.EvidencePatchSetApplicatorTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.AgentRunner.PatchCapture
  alias Conveyor.Evidence.PatchSetApplicator
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.WorkspaceMaterialization
  alias Conveyor.Sandbox.WorkspaceCleanup

  test "applies PatchSet to a clean gate workspace and records head tree digest" do
    fixture = patch_fixture!("patch-apply")

    File.write!(Path.join(fixture.repo_path, "sample.txt"), "changed\n")
    File.write!(Path.join(fixture.repo_path, "added.txt"), "added\n")

    patch_set =
      PatchCapture.capture!(%{path: fixture.repo_path, base_commit: fixture.base_commit},
        run_attempt_id: fixture.run_attempt.id,
        blob_root: fixture.blob_root
      )

    assert {:ok, workspace} =
             PatchSetApplicator.apply_patch_set(patch_set,
               blob_root: fixture.blob_root,
               workspace_root: fixture.workspace_root
             )

    assert workspace.purpose == :gate
    assert workspace.base_commit == fixture.base_commit
    assert workspace.applied_patch_sha256 == patch_set.patch_sha256
    assert workspace.mount_mode == :read_write
    assert workspace.head_tree_sha256 == WorkspaceCleanup.tree_sha256(workspace.path)
    assert File.read!(Path.join(workspace.path, "sample.txt")) == "changed\n"
    assert File.read!(Path.join(workspace.path, "added.txt")) == "added\n"

    run_attempt = get_by_id!(RunAttempt, fixture.run_attempt.id)
    assert run_attempt.patch_set_id == patch_set.id
    assert run_attempt.head_tree_sha256 == workspace.head_tree_sha256

    assert [stored_workspace] = Ash.read!(WorkspaceMaterialization, domain: Factory)
    assert stored_workspace.id == workspace.id
  end

  test "rejects PatchSet when the expected base commit differs" do
    fixture = patch_fixture!("patch-base-mismatch")
    File.write!(Path.join(fixture.repo_path, "sample.txt"), "changed\n")

    captured_patch_set =
      PatchCapture.capture!(%{path: fixture.repo_path, base_commit: fixture.base_commit},
        run_attempt_id: fixture.run_attempt.id,
        blob_root: fixture.blob_root
      )

    patch_set =
      Ash.create!(
        PatchSet,
        %{
          run_attempt_id: fixture.run_attempt.id,
          base_commit: "different-base",
          patch_ref: captured_patch_set.patch_ref,
          patch_sha256: captured_patch_set.patch_sha256,
          changed_files: captured_patch_set.changed_files,
          added_files: captured_patch_set.added_files,
          deleted_files: captured_patch_set.deleted_files,
          renamed_files: captured_patch_set.renamed_files,
          lines_added: captured_patch_set.lines_added,
          lines_deleted: captured_patch_set.lines_deleted,
          touches_locked_paths: captured_patch_set.touches_locked_paths,
          applies_cleanly: captured_patch_set.applies_cleanly
        },
        domain: Factory
      )

    assert {:error, finding} =
             PatchSetApplicator.apply_patch_set(patch_set,
               blob_root: fixture.blob_root,
               workspace_root: fixture.workspace_root
             )

    assert finding["category"] == "unexpected_base"
    assert finding["details"]["patch_set_base_commit"] == "different-base"
    assert finding["details"]["run_attempt_base_commit"] == fixture.base_commit
    assert Ash.read!(WorkspaceMaterialization, domain: Factory) == []
  end

  defp patch_fixture!(label) do
    repo_path = git_workspace!(label)
    base_commit = git!(repo_path, ["rev-parse", "HEAD"])
    blob_root = temp_dir!("#{label}-blobs")
    workspace_root = temp_dir!("#{label}-gate")

    project =
      Ash.create!(
        Project,
        %{name: "Patch applicator sample", local_path: repo_path, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Patch applicator plan",
          intent: "Apply PatchSet to clean workspace.",
          source_document: "docs/patch-applicator.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Patch applicator epic", description: "Evidence."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Patch applicator slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, base_commit), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: base_commit,
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-patch-apply"
        },
        domain: Factory
      )

    %{
      base_commit: base_commit,
      blob_root: blob_root,
      repo_path: repo_path,
      run_attempt: run_attempt,
      workspace_root: workspace_root
    }
  end

  defp git_workspace!(label) do
    path = temp_dir!(label)
    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "conveyor@example.test"])
    git!(path, ["config", "user.name", "Conveyor Test"])
    File.write!(Path.join(path, "sample.txt"), "original\n")
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "base"])
    path
  end

  defp git!(path, args) do
    {output, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(output)
  end

  defp run_spec_attrs(slice_id, base_commit) do
    run_spec_sha256 = digest("run-spec-patch-apply")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/patch-apply.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "fake"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "evidence",
            "kind" => "evidence",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
