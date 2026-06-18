defmodule Conveyor.EvidenceRecorderTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.AgentRunner.PatchCapture
  alias Conveyor.Evidence.Recorder
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Evidence
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBundle
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  test "writes evidence packet artifacts and regenerates projection idempotently" do
    fixture = evidence_fixture!("evidence-recorder")
    File.write!(Path.join(fixture.repo_path, "sample.txt"), "changed\n")

    patch_set =
      PatchCapture.capture!(%{path: fixture.repo_path, base_commit: fixture.base_commit},
        run_attempt_id: fixture.run_attempt.id,
        blob_root: fixture.blob_root
      )

    acceptance_criteria = [criterion("AC-001", ["tests/sample_test.exs::passes"])]
    verification = verification_result([test_result("tests/sample_test.exs::passes", "passed")])

    first =
      Recorder.record!(fixture.run_attempt, patch_set, acceptance_criteria, verification,
        blob_root: fixture.blob_root,
        projection_root: fixture.projection_root
      )

    run_dir = Path.join(fixture.projection_root, fixture.run_attempt.id)
    assert File.exists?(Path.join(run_dir, "manifest.json"))
    assert File.exists?(Path.join(run_dir, "evidence.json"))
    assert File.exists?(Path.join(run_dir, "dossier.md"))
    assert File.exists?(Path.join(run_dir, "diff.patch"))
    assert File.exists?(Path.join(run_dir, "logs/verification.json"))

    evidence_json = File.read!(Path.join(run_dir, "evidence.json")) |> Jason.decode!()
    assert evidence_json["schema_version"] == "conveyor.evidence_packet@1"

    assert get_in(evidence_json, ["acceptance_results", Access.at(0), "evidence_status"]) ==
             "passed"

    dossier = File.read!(Path.join(run_dir, "dossier.md"))
    assert dossier =~ "RunAttempt: #{fixture.run_attempt.id}"
    assert dossier =~ "AC-001: passed"

    stored_attempt = get_by_id!(RunAttempt, fixture.run_attempt.id)
    assert stored_attempt.status == :evidence_recorded

    assert [evidence] = Ash.read!(Evidence, domain: Factory)
    assert evidence.diff_ref == "diff.patch"
    assert [%{"id" => "AC-001", "evidence_status" => "passed"}] = evidence.acceptance_results

    second =
      Recorder.record!(stored_attempt, patch_set, acceptance_criteria, verification,
        blob_root: fixture.blob_root,
        projection_root: fixture.projection_root
      )

    assert second.projection.manifest_sha256 == first.projection.manifest_sha256
    assert second.projection.bundle_root_sha256 == first.projection.bundle_root_sha256
    assert length(Ash.read!(Evidence, domain: Factory)) == 1
    assert length(Ash.read!(RunBundle, domain: Factory)) == 1
  end

  defp evidence_fixture!(label) do
    repo_path = git_workspace!(label)
    base_commit = git!(repo_path, ["rev-parse", "HEAD"])

    project =
      Ash.create!(
        Project,
        %{name: "Evidence recorder sample", local_path: repo_path, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Evidence recorder plan",
          intent: "Write evidence packet.",
          source_document: "docs/evidence-recorder.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Evidence recorder epic", description: "Evidence."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Evidence recorder slice", position: 1},
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
          trace_id: "trace-evidence-recorder"
        },
        domain: Factory
      )

    %{
      base_commit: base_commit,
      blob_root: temp_dir!("#{label}-blobs"),
      projection_root: temp_dir!("#{label}-projection"),
      repo_path: repo_path,
      run_attempt: run_attempt
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

  defp criterion(id, required_test_refs) do
    %{
      "id" => id,
      "text" => "#{id} works",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-1"],
      "required_test_refs" => required_test_refs,
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp verification_result(tests) do
    %{"suites" => [%{"commands" => [%{"attempts" => [%{"tests" => tests}]}]}]}
  end

  defp test_result(id, status), do: %{"id" => id, "name" => id, "status" => status}

  defp run_spec_attrs(slice_id, base_commit) do
    run_spec_sha256 = digest("run-spec-evidence-recorder")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/evidence-recorder.json",
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
