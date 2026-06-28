defmodule Conveyor.StationsRecordEvidenceTest do
  # TEST-ONLY behavioral unit test for the RecordEvidence station (plan unit U10).
  #
  # Output contract (happy path): run/2 returns
  #   {:ok, %{"evidence_id" => _, "projection_path" => _, "security_findings" => _}}
  #
  # Hermetic happy path: the diff blob is written directly to a temp blob_root and referenced by
  # a real PatchSet, so Conveyor.Evidence.Recorder.record!/5 reads it back, writes the evidence
  # packet, transitions the attempt (:running -> :evidence_recorded), and projects the run. No
  # AgentBrief is seeded, so acceptance criteria are empty (AcceptanceMapper handles []). The
  # station does NOT pass a projection_root, so the projection lands under the Recorder default
  # ".conveyor/runs/<run_attempt_id>" relative to CWD (writable in tests).
  #
  # Failure mode: ArgumentError when patch_set_id is nil (checked before any DB / context access).
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
  alias Conveyor.Stations.RecordEvidence

  @base_commit String.duplicate("c", 40)

  test "run/2 records evidence and returns the evidence id, projection path, and findings" do
    fixture = fixture!("record-evidence-happy")

    input = %{
      "patch_set_id" => fixture.patch_set.id,
      # AcceptanceMapper.test_results_by_id/1 reads the "suites" key; empty suites is a
      # valid no-results verification result (no AgentBrief seeded -> empty criteria).
      "verification_result" => %{"suites" => []},
      "blob_root" => fixture.blob_root
    }

    assert {:ok, output} =
             RecordEvidence.run(input, %{run_attempt: fixture.run_attempt})

    assert is_binary(output["evidence_id"])
    assert is_binary(output["projection_path"])
    # benign content yields no redaction findings.
    assert is_list(output["security_findings"])
  end

  test "run/2 raises ArgumentError when patch_set_id is nil" do
    # patch_set_id nil raises before any context access; a shaped context keeps the
    # type checker happy without affecting the assertion.
    assert_raise ArgumentError, fn ->
      RecordEvidence.run(%{"patch_set_id" => nil}, %{run_attempt: %{slice_id: nil}})
    end
  end

  defp fixture!(label) do
    blob_root = temp_dir!("#{label}-blobs")

    project =
      Ash.create!(
        Project,
        %{name: "RecordEvidence #{label}", local_path: temp_dir!(label), default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "RecordEvidence plan",
          intent: "Exercise the record_evidence station.",
          source_document: "docs/record-evidence.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "RecordEvidence epic", description: "Evidence."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "RecordEvidence slice", position: 1},
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
          base_commit: @base_commit,
          # :running is required for the Recorder's :record_evidence lifecycle transition to fire.
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-record-evidence"
        },
        domain: Factory
      )

    diff = "--- a/sample.txt\n+++ b/sample.txt\n@@ -1 +1 @@\n-original\n+changed\n"
    blob = BlobStore.write!(diff, blob_root: blob_root)

    patch_set =
      Ash.create!(
        PatchSet,
        %{
          run_attempt_id: run_attempt.id,
          base_commit: @base_commit,
          patch_ref: blob.ref,
          patch_sha256: digest(diff),
          changed_files: ["sample.txt"],
          lines_added: 1,
          lines_deleted: 1
        },
        domain: Factory
      )

    %{run_attempt: run_attempt, patch_set: patch_set, blob_root: blob_root}
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-record-evidence")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/record-evidence.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: @base_commit,
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
            "key" => "record_evidence",
            "module" => "Conveyor.Stations.RecordEvidence",
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

  defp temp_dir!(label) do
    path =
      Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
