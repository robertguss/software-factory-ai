defmodule Conveyor.RunReviewerTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Jobs.RunReviewer

  test "runs reviewer session over dossier bytes and persists schema-valid review" do
    fixture = reviewer_fixture!("run-reviewer")
    reviewer_profile_id = Ash.UUID.generate()
    run_prompt_id = Ash.UUID.generate()
    parent = self()

    reviewer = fn context ->
      send(parent, {:review_context, context.dossier, context.dossier_sha256, Map.keys(context)})

      %{
        "schema_version" => "conveyor.review@1",
        "run_spec_sha256" => raw_sha256(context.run_spec.run_spec_sha256),
        "dossier_sha256" => context.dossier_sha256,
        "reviewer" => %{
          "actor_id" => context.reviewer_session_id,
          "profile_id" => context.reviewer_profile_id
        },
        "rubric_version" => context.rubric_version,
        "decision" => "needs_rework",
        "recommendation" => "rework",
        "summary" => "Dossier evidence is missing an edge-case check.",
        "findings" => [
          %{
            "severity" => "warning",
            "category" => "review",
            "message" => "Add an edge-case test.",
            "artifact_refs" => ["dossier.md"],
            "next_actions" => [
              %{"kind" => "rerun_station", "label" => "Rerun reviewer after test update."}
            ]
          }
        ],
        "checks" => [
          %{
            "name" => "acceptance",
            "status" => "fail",
            "evidence_refs" => ["dossier.md"],
            "summary" => "Required edge-case evidence was absent."
          }
        ]
      }
    end

    result =
      RunReviewer.run!(fixture.run_attempt,
        blob_root: fixture.blob_root,
        reviewer_profile_id: reviewer_profile_id,
        run_prompt_id: run_prompt_id,
        reviewer: reviewer
      )

    assert_received {:review_context, dossier, dossier_sha256, context_keys}
    assert dossier == fixture.dossier
    assert dossier_sha256 == BlobStore.sha256(fixture.dossier)
    refute :live_session in context_keys

    assert result.reviewer_session.role == :reviewer
    assert result.reviewer_session.status == :succeeded
    assert result.reviewer_session.run_prompt_id == run_prompt_id
    assert result.reviewer_session.agent_profile_id == reviewer_profile_id
    assert result.review.reviewer_session_id == result.reviewer_session.id
    assert result.review.reviewer_profile_id == reviewer_profile_id
    assert result.review.dossier_sha256 == dossier_sha256
    assert result.review.rubric_version == "reviewer@1"
    assert result.review.decision == :needs_rework
    assert result.review.recommendation == :rework

    assert_schema_valid!(result.review_json)

    assert [stored_review] = Ash.read!(Review, domain: Factory)
    assert stored_review.id == result.review.id
    assert stored_review.dossier_sha256 == result.review.dossier_sha256

    assert [stored_session] = Ash.read!(AgentSession, domain: Factory)
    assert stored_session.id == result.reviewer_session.id
    assert stored_session.status == :succeeded
  end

  test "default reviewer emits an accepted review tied to the dossier digest" do
    fixture = reviewer_fixture!("run-reviewer-default")

    result = RunReviewer.run!(fixture.run_attempt, blob_root: fixture.blob_root)

    assert result.review.decision == :accepted
    assert result.review.recommendation == :merge
    assert result.review.dossier_sha256 == BlobStore.sha256(fixture.dossier)
    assert result.review_json["dossier_sha256"] == result.review.dossier_sha256
    assert_schema_valid!(result.review_json)
  end

  defp reviewer_fixture!(label) do
    project =
      Ash.create!(
        Project,
        %{name: "Reviewer sample", local_path: "/tmp/#{label}", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Reviewer plan",
          intent: "Review dossier.",
          source_document: "docs/reviewer.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Reviewer epic", description: "Review."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Reviewer slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: "abc123",
          status: :evidence_recorded,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-reviewer"
        },
        domain: Factory
      )

    blob_root = temp_dir!("#{label}-blobs")
    dossier = "# Run Dossier\n\nAcceptance evidence.\n"
    blob = BlobStore.write!(dossier, blob_root: blob_root)

    Ash.create!(
      Artifact,
      %{
        run_attempt_id: run_attempt.id,
        kind: "manifest",
        media_type: "text/markdown",
        projection_path: "dossier.md",
        blob_ref: blob.ref,
        sha256: blob.sha256,
        raw_sha256: blob.sha256,
        redacted_sha256: blob.sha256,
        redaction_findings: [],
        size_bytes: blob.size_bytes,
        subject_kind: "run_attempt",
        producer: "evidence-recorder",
        schema_version: "conveyor.evidence_packet@1",
        sensitivity: :internal
      },
      domain: Factory
    )

    %{blob_root: blob_root, dossier: dossier, run_attempt: run_attempt}
  end

  defp assert_schema_valid!(review_json) do
    schema =
      "docs/schemas/conveyor.review@1.json"
      |> File.read!()
      |> Jason.decode!()

    root = JSV.build!(schema, warnings: :silent)
    assert {:ok, _validated} = JSV.validate(review_json, root)
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-reviewer")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/reviewer.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
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
            "key" => "review",
            "kind" => "review",
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

  defp digest(label), do: "sha256:" <> BlobStore.sha256(label)
  defp raw_sha256("sha256:" <> digest), do: raw_sha256(digest)
  defp raw_sha256(digest), do: digest
end
