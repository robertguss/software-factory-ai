defmodule Conveyor.Factory.ArtifactHealthResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.GateHealth
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.ReviewerHealth
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBundle
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Artifact sample", local_path: "/tmp/artifact-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Artifact plan",
          intent: "Record artifacts and health summaries.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Artifact epic", description: "Artifacts."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Artifact slice", position: 1},
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
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-artifact"
        },
        domain: Factory
      )

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          station: "artifact",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "#{run_attempt.id}:artifact:#{digest("station")}:1",
          input_sha256: digest("input")
        },
        domain: Factory
      )

    %{project: project, run_attempt: run_attempt, station_run: station_run}
  end

  test "artifacts enforce projection identity and sensitivity enum", %{
    run_attempt: run_attempt,
    station_run: station_run
  } do
    attrs = artifact_attrs(run_attempt.id, station_run.id, digest("artifact"), 1_024)

    artifact = Ash.create!(Artifact, attrs, domain: Factory)
    assert artifact.sensitivity == :internal
    assert artifact.sha256 == digest("artifact")

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(Artifact, attrs, domain: Factory)
    end

    same_content_other_path =
      Ash.create!(
        Artifact,
        Map.put(attrs, :projection_path, "artifacts/runs/attempt-1/copy.txt"),
        domain: Factory
      )

    assert same_content_other_path.sha256 == artifact.sha256
    assert same_content_other_path.size_bytes == artifact.size_bytes

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(
        Artifact,
        attrs
        |> Map.put(:projection_path, "artifacts/runs/attempt-1/secret.txt")
        |> Map.put(:sensitivity, :secret),
        domain: Factory
      )
    end
  end

  test "run bundles track canonical run manifests", %{run_attempt: run_attempt} do
    bundle =
      Ash.create!(
        RunBundle,
        %{
          run_attempt_id: run_attempt.id,
          manifest_ref: "artifacts/runs/attempt-1/manifest.json",
          manifest_sha256: digest("manifest"),
          bundle_root_sha256: digest("bundle-root"),
          schema_version: "conveyor.run_bundle@1",
          projection_path: "artifacts/runs/attempt-1"
        },
        domain: Factory
      )

    assert bundle.projection_status == :pending
    assert bundle.bundle_root_sha256 == digest("bundle-root")

    updated = Ash.update!(bundle, %{projection_status: :projected}, domain: Factory)
    assert updated.projection_status == :projected
  end

  test "reviewer health records fixture-suite pass/fail summaries" do
    health =
      Ash.create!(
        ReviewerHealth,
        %{
          reviewer_profile_id: Ash.UUID.generate(),
          rubric_version: "reviewer@1",
          fixture_suite_version: "fixtures@2026-06-17",
          passed: false,
          failures: [
            %{"fixture" => "rejects-unsafe-diff", "message" => "Reviewer accepted unsafe diff."}
          ]
        },
        domain: Factory
      )

    refute health.passed
    assert [%{"fixture" => "rejects-unsafe-diff"}] = health.failures

    updated = Ash.update!(health, %{passed: true, failures: []}, domain: Factory)
    assert updated.passed
    assert updated.failures == []
  end

  test "gate health enforces one freshness summary per project and key", %{project: project} do
    attrs = gate_health_attrs(project.id, digest("freshness"))

    health = Ash.create!(GateHealth, attrs, domain: Factory)
    assert health.project_id == project.id
    assert health.freshness_key_sha256 == digest("freshness")

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(GateHealth, attrs, domain: Factory)
    end

    next_health =
      Ash.create!(GateHealth, gate_health_attrs(project.id, digest("freshness-next")),
        domain: Factory
      )

    assert next_health.freshness_key_sha256 == digest("freshness-next")
  end

  defp artifact_attrs(run_attempt_id, station_run_id, sha256, size_bytes) do
    %{
      run_attempt_id: run_attempt_id,
      station_run_id: station_run_id,
      kind: "run-log",
      media_type: "text/plain",
      projection_path: "artifacts/runs/attempt-1/log.txt",
      blob_ref: "cas/#{sha256}",
      sha256: sha256,
      size_bytes: size_bytes,
      subject_kind: "run_attempt",
      producer: "gate",
      schema_version: "conveyor.artifact@1",
      sensitivity: :internal
    }
  end

  defp gate_health_attrs(project_id, freshness_key_sha256) do
    %{
      project_id: project_id,
      freshness_key_sha256: freshness_key_sha256,
      gate_version: "gate@1",
      gate_code_sha256: digest("gate-code"),
      policy_sha256: digest("policy"),
      test_pack_sha256: digest("test-pack"),
      container_image_digest: digest("image"),
      code_quality_profile_sha256: digest("code-quality"),
      canary_suite_version: "canary@1",
      runcheck_schema_version: "runcheck@1",
      last_run_ref: "runs/attempt-1",
      passed: true
    }
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-artifact")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "artifact",
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

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
