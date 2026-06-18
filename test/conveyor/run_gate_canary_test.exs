defmodule Conveyor.RunGateCanaryTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
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

  test "runs known-good and all enabled mutants through the gate-only path" do
    summary = run_canary(FixtureGateStage)

    assert summary["passed"]
    assert summary["known_good"]["outcome"] == "passed"
    assert summary["case_count"] == 9
    assert summary["false_negative_count"] == 0
    assert summary["false_positive_count"] == 0
    assert Enum.all?(summary["mutants"], &(&1["outcome"] == "rejected_expected"))
    assert Enum.all?(summary["mutants"], & &1["matched_expected"])
  end

  test "classifies passed mutants as false negatives" do
    summary = run_canary(FalseNegativeStage)

    refute summary["passed"]
    assert summary["known_good"]["outcome"] == "passed"
    assert summary["false_negative_count"] == 8
    assert Enum.all?(summary["mutants"], &(&1["outcome"] == "false_negative"))
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

  defp gate_context do
    %{
      run_attempt_id: "run-attempt-canary",
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract"
    }
  end
end
