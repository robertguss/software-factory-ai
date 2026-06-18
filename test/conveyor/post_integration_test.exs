defmodule Conveyor.PostIntegrationTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.HumanIntegration
  alias Conveyor.PostIntegration

  test "exact external patch is done eligible and records passed verification" do
    fixture = fixture!("exact")
    external_commit = commit_change!(fixture.repo, "accepted")
    accepted_patch = git!(fixture.repo, ["diff", fixture.base_commit, external_commit])
    create_patch_set!(fixture.run_attempt, fixture.blob_root, accepted_patch)
    approval = record_approval!(fixture.run_attempt, external_commit)

    result =
      PostIntegration.check!(approval.id,
        blob_root: fixture.blob_root,
        protected_path_globs: ["priv/repo/migrations/**"]
      )

    assert result.done_eligible?
    assert result.external_change.equivalence == :exact
    assert result.external_change.verification_status == :passed
    assert result.patch_equivalence.accepted_hunks_present
    assert result.patch_equivalence.protected_paths_changed == []
  end

  test "external patch with unprotected human edits is done eligible" do
    fixture = fixture!("human-edits")
    accepted_commit = commit_change!(fixture.repo, "accepted")
    accepted_patch = git!(fixture.repo, ["diff", fixture.base_commit, accepted_commit])
    external_commit = commit_change!(fixture.repo, "human-edits")
    create_patch_set!(fixture.run_attempt, fixture.blob_root, accepted_patch)
    approval = record_approval!(fixture.run_attempt, external_commit)

    result = PostIntegration.check!(approval.id, blob_root: fixture.blob_root)

    assert result.done_eligible?
    assert result.external_change.equivalence == :equivalent_with_human_edits
    assert result.patch_equivalence.extra_files_changed == ["README.md"]
  end

  test "divergent external patch blocks done eligibility" do
    fixture = fixture!("divergent")
    accepted_commit = commit_change!(fixture.repo, "accepted")
    accepted_patch = git!(fixture.repo, ["diff", fixture.base_commit, accepted_commit])
    external_commit = commit_change!(fixture.repo, "divergent")
    create_patch_set!(fixture.run_attempt, fixture.blob_root, accepted_patch)
    approval = record_approval!(fixture.run_attempt, external_commit)

    result = PostIntegration.check!(approval.id, blob_root: fixture.blob_root)

    refute result.done_eligible?
    assert result.external_change.equivalence == :divergent
    assert result.external_change.verification_status == :failed
  end

  defp fixture!(label) do
    repo = temp_dir!("post-integration-#{label}")
    blob_root = temp_dir!("post-integration-blobs-#{label}")
    git!(repo, ["init", "-b", "main"])
    git!(repo, ["config", "user.email", "conveyor@example.test"])
    git!(repo, ["config", "user.name", "Conveyor Test"])
    File.write!(Path.join(repo, "app.py"), "value = 1\n")
    File.write!(Path.join(repo, "README.md"), "base\n")
    git!(repo, ["add", "."])
    git!(repo, ["commit", "-m", "base"])
    base_commit = git!(repo, ["rev-parse", "HEAD"])

    project =
      Ash.create!(
        Project,
        %{name: "Post integration", local_path: repo, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Post integration plan",
          intent: "Check external integration.",
          source_document: "docs/post.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Post integration", description: "Post."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Post slice", position: 1}, domain: Factory)

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, base_commit), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: base_commit,
          status: :gated,
          outcome: :accepted,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-post"
        },
        domain: Factory
      )

    %{blob_root: blob_root, repo: repo, base_commit: base_commit, run_attempt: run_attempt}
  end

  defp commit_change!(repo, "accepted") do
    File.write!(Path.join(repo, "app.py"), "value = 2\n")
    git!(repo, ["add", "app.py"])
    git!(repo, ["commit", "-m", "accepted"])
    git!(repo, ["rev-parse", "HEAD"])
  end

  defp commit_change!(repo, "human-edits") do
    File.write!(Path.join(repo, "README.md"), "base\nhuman note\n")
    git!(repo, ["add", "README.md"])
    git!(repo, ["commit", "-m", "human edits"])
    git!(repo, ["rev-parse", "HEAD"])
  end

  defp commit_change!(repo, "divergent") do
    git!(repo, ["checkout", "-B", "divergent", "HEAD~1"])
    File.write!(Path.join(repo, "app.py"), "value = 3\n")
    git!(repo, ["add", "app.py"])
    git!(repo, ["commit", "-m", "divergent"])
    git!(repo, ["rev-parse", "HEAD"])
  end

  defp create_patch_set!(run_attempt, blob_root, patch) do
    blob = BlobStore.write!(patch, blob_root: blob_root)

    Ash.create!(
      PatchSet,
      %{
        run_attempt_id: run_attempt.id,
        base_commit: run_attempt.base_commit,
        patch_ref: blob.ref,
        patch_sha256: digest_bytes(patch),
        changed_files: ["app.py"],
        lines_added: 1,
        lines_deleted: 1
      },
      domain: Factory
    )
  end

  defp record_approval!(run_attempt, external_commit) do
    HumanIntegration.record!(
      run_attempt_id: run_attempt.id,
      actor: "human@example.test",
      external_commit: external_commit
    )
  end

  defp run_spec_attrs(slice_id, base_commit) do
    run_spec_sha256 = digest("run-spec-post")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/post.json",
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
            "key" => "post_integration",
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

  defp git!(repo, args) do
    {output, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(output)
  end

  defp temp_dir!(label) do
    path = Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
  defp digest_bytes(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
