defmodule Conveyor.RunGateCanaryTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.GateHealth
  alias Conveyor.Gate.StageResult
  alias Conveyor.Jobs.RunGateCanary

  defmodule FixtureGateStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(%{patch_set: %{kind: :known_good}}, _opts) do
      %StageResult{key: "fixture_gate", status: :passed, required?: true}
    end

    def run(%{patch_set: %{expected_catch: expected}}, _opts) do
      %StageResult{
        key: expected["stage"],
        status: :failed,
        required?: true,
        findings: [
          %{
            "category" => expected["category"],
            "severity" => "blocking",
            "message" => expected["reason"]
          }
        ]
      }
    end
  end

  defmodule FalseNegativeStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts), do: %StageResult{key: "bad_gate", status: :passed, required?: true}
  end

  defmodule FalsePositiveStage do
    @behaviour Conveyor.Gate.Stage

    # Wrongly rejects the known-good fixture (a false positive) while still
    # rejecting every mutant for the expected reason.
    @impl true
    def run(%{patch_set: %{kind: :known_good}}, _opts) do
      %StageResult{
        key: "fixture_gate",
        status: :failed,
        required?: true,
        findings: [
          %{"category" => "spurious", "severity" => "blocking", "message" => "wrongly rejected"}
        ]
      }
    end

    def run(%{patch_set: %{expected_catch: expected}}, _opts) do
      %StageResult{
        key: expected["stage"],
        status: :failed,
        required?: true,
        findings: [
          %{
            "category" => expected["category"],
            "severity" => "blocking",
            "message" => expected["reason"]
          }
        ]
      }
    end
  end

  test "runs known-good and all enabled mutants through the gate-only path" do
    summary = run_canary(FixtureGateStage)

    assert summary["passed"]
    assert summary["known_good"]["outcome"] == "passed"
    assert summary["case_count"] == 9
    assert summary["false_negative_count"] == 0
    assert summary["false_positive_count"] == 0
    assert summary["ci_exit_code"] == 0
    assert Enum.all?(summary["mutants"], &(&1["outcome"] == "rejected_expected"))
    assert Enum.all?(summary["mutants"], & &1["matched_expected"])
  end

  test "classifies passed mutants as false negatives" do
    summary = run_canary(FalseNegativeStage)

    refute summary["passed"]
    assert summary["known_good"]["outcome"] == "passed"
    assert summary["false_negative_count"] == 8
    assert summary["ci_exit_code"] == 6
    assert Enum.all?(summary["mutants"], &(&1["outcome"] == "false_negative"))
  end

  test "classifies a rejected known-good fixture as a false positive with the gate-failed exit code" do
    summary = run_canary(FalsePositiveStage)

    refute summary["passed"]
    assert summary["known_good"]["outcome"] == "false_positive"
    assert summary["false_positive_count"] == 1
    assert summary["false_negative_count"] == 0
    # A false positive is release-blocking but distinct from a false negative (6).
    assert summary["ci_exit_code"] == 1
  end

  test "writes a canary run artifact when run attempt and blob root are provided" do
    blob_root = temp_dir!("gate-canary-run")
    fixture = create_artifact_run!(blob_root: blob_root)

    summary =
      run_canary(FixtureGateStage,
        blob_root: blob_root,
        run_attempt_id: fixture.run_attempt.id
      )

    assert summary["artifact_ref"] == "canary/mutants.json"
    assert is_binary(summary["blob_ref"])

    [artifact] =
      Artifact
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.kind == "canary_run" and &1.run_attempt_id == fixture.run_attempt.id))

    assert artifact.schema_version == "conveyor.gate_canary_run@1"

    written =
      artifact.blob_ref
      |> BlobStore.read!(blob_root: blob_root)
      |> Jason.decode!()

    assert written["passed"]
    assert written["case_count"] == 9
  end

  test "updates GateHealth summary for the current freshness key" do
    fixture = create_artifact_run!(blob_root: temp_dir!("gate-canary-health"))

    summary =
      run_canary(FixtureGateStage,
        project_id: fixture.project.id,
        context: gate_context(fixture.project.id)
      )

    assert summary["gate_health_id"]

    [health] =
      GateHealth
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.project_id == fixture.project.id))

    assert health.passed
    assert health.false_negative_count == 0
    assert health.last_run_ref == "samples/tasks_service/.conveyor/canary/mutants.json"
    assert health.freshness_key_sha256
  end

  defp run_canary(stage, opts \\ []) do
    RunGateCanary.run!(
      Keyword.merge(
        [
          stages: [%{key: "fixture_gate", module: stage}],
          context: gate_context()
        ],
        opts
      )
    )
  end

  defp gate_context(project_id \\ nil) do
    %{
      project_id: project_id,
      run_attempt_id: "run-attempt-canary",
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      test_pack_sha256: "sha256:test-pack",
      container_image_digest: "sha256:image",
      code_quality_profile_sha256: "sha256:quality",
      canary_suite_version: "canary@1",
      runcheck_schema_version: "conveyor.run_bundle@1"
    }
  end
end
