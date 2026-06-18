defmodule Conveyor.FactoryFixtures do
  @moduledoc false

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun

  def create_artifact_run!(opts \\ []) do
    blob_root = Keyword.fetch!(opts, :blob_root)
    artifact_content = Keyword.get(opts, :artifact_content, "artifact\n")
    projection_path = Keyword.get(opts, :projection_path, "evidence.json")
    sha256 = digest_bytes(artifact_content)

    project =
      Ash.create!(
        Project,
        %{
          name: Keyword.get(opts, :project_name, "Replay fixture"),
          local_path: Keyword.get(opts, :local_path, "/tmp/replay-fixture"),
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Replay fixture plan",
          intent: "Regenerate artifacts.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Replay fixture epic", description: "Artifacts."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Replay fixture slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, opts), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: run_spec.base_commit,
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-replay"
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

    blob = BlobStore.write!(artifact_content, blob_root: blob_root)

    artifact =
      Ash.create!(
        Artifact,
        %{
          run_attempt_id: run_attempt.id,
          station_run_id: station_run.id,
          kind: "run-log",
          media_type: "text/plain",
          projection_path: projection_path,
          blob_ref: blob.ref,
          sha256: sha256,
          size_bytes: byte_size(artifact_content),
          subject_kind: "run_attempt",
          producer: "gate",
          schema_version: "conveyor.artifact@1",
          sensitivity: :internal
        },
        domain: Factory
      )

    %{
      artifact: artifact,
      artifact_content: artifact_content,
      project: project,
      projection_path: projection_path,
      run_attempt: run_attempt,
      station_run: station_run
    }
  end

  def temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-#{label}-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    # System.unique_integer resets per VM, so without the timestamp + an explicit wipe a
    # fresh run can land on a leftover temp dir from a prior run (a populated git repo),
    # which surfaces as flaky "nothing to commit" / stale-stat git failures.
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp run_spec_attrs(slice_id, opts) do
    run_spec_sha256 = digest("run-spec-replay")
    base_commit = Keyword.get(opts, :base_commit, "abc123")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
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

  defp digest(label), do: "sha256:" <> digest_bytes(label)
  defp digest_bytes(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
