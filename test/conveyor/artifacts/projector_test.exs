defmodule Conveyor.Artifacts.ProjectorTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Artifacts.Projector
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBundle
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun

  defmodule RecordingBackend do
    @moduledoc false

    @behaviour Projector

    @impl Projector
    def project_run!(run_attempt, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:project_run, run_attempt.id, opts})

      %Projector.Result{
        run_attempt_id: run_attempt.id,
        projection_path: "/tmp/recorded",
        artifact_count: 0,
        manifest_sha256: "sha256:manifest",
        bundle_root_sha256: "sha256:bundle"
      }
    end
  end

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Projector sample", local_path: "/tmp/projector-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Projector plan",
          intent: "Regenerate artifact projections.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Projector epic", description: "Artifacts."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Projector slice", position: 1},
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
          trace_id: "trace-projector"
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

    %{
      blob_root: temp_dir!("blobs"),
      projection_root: temp_dir!("projection"),
      run_attempt: run_attempt,
      station_run: station_run
    }
  end

  test "regenerates a run projection from content-addressed blobs", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    content = "pytest passed\n"
    sha256 = digest_bytes(content)
    blob = BlobStore.write!(content, blob_root: blob_root)

    create_artifact!(
      run_attempt,
      station_run,
      blob.ref,
      sha256,
      byte_size(content),
      "logs/pytest.txt"
    )

    first =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    projected_file = Path.join([projection_root, run_attempt.id, "logs/pytest.txt"])
    assert File.read!(projected_file) == content
    assert first.artifact_count == 1

    assert [bundle] = Ash.read!(RunBundle, domain: Factory)
    assert bundle.projection_status == :projected
    assert bundle.bundle_root_sha256 == first.bundle_root_sha256

    File.rm_rf!(Path.join(projection_root, run_attempt.id))

    second =
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )

    assert File.read!(projected_file) == content
    assert second.manifest_sha256 == first.manifest_sha256
    assert second.bundle_root_sha256 == first.bundle_root_sha256
  end

  test "rejects corrupted blobs before writing projection files", %{
    blob_root: blob_root,
    projection_root: projection_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    expected_sha256 = digest_bytes("expected")
    blob_ref = BlobStore.ref_for_sha256!(expected_sha256)
    corrupt_blob!(blob_root, blob_ref, "corrupted")

    create_artifact!(
      run_attempt,
      station_run,
      blob_ref,
      expected_sha256,
      byte_size("expected"),
      "logs/bad.txt"
    )

    assert_raise ArgumentError, ~r/digest mismatch/, fn ->
      Projector.project_run!(run_attempt,
        blob_root: blob_root,
        projection_root: projection_root
      )
    end

    refute File.exists?(Path.join([projection_root, run_attempt.id, "logs/bad.txt"]))
  end

  test "delegates to the selected projector backend", %{run_attempt: run_attempt} do
    result =
      Projector.project_run!(run_attempt,
        backend: RecordingBackend,
        test_pid: self(),
        projection_root: "/unused"
      )

    assert_receive {:project_run, run_attempt_id, opts}
    assert run_attempt_id == run_attempt.id
    refute Keyword.has_key?(opts, :backend)
    assert Keyword.fetch!(opts, :projection_root) == "/unused"
    assert result.projection_path == "/tmp/recorded"
  end

  defp create_artifact!(run_attempt, station_run, blob_ref, sha256, size_bytes, projection_path) do
    Ash.create!(
      Artifact,
      %{
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        kind: "run-log",
        media_type: "text/plain",
        projection_path: projection_path,
        blob_ref: blob_ref,
        sha256: sha256,
        size_bytes: size_bytes,
        subject_kind: "run_attempt",
        producer: "gate",
        schema_version: "conveyor.artifact@1",
        sensitivity: :internal
      },
      domain: Factory
    )
  end

  defp corrupt_blob!(blob_root, blob_ref, content) do
    path = BlobStore.path_for!(blob_ref, blob_root: blob_root)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-projector-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-projector")

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

  defp digest(label), do: "sha256:" <> digest_bytes(label)
  defp digest_bytes(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
