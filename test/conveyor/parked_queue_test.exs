defmodule Conveyor.ParkedQueueTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer
  alias Conveyor.ParkedQueue

  defmodule PassStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts), do: %{status: :passed, evidence_refs: ["evidence.json"]}
  end

  setup do
    fixture = create_artifact_run!(blob_root: temp_dir!("parked-queue"))
    slice = get_by_id!(Slice, fixture.run_attempt.slice_id)

    run_attempt =
      Ash.update!(fixture.run_attempt, %{status: :reviewed, outcome: :none}, domain: Factory)

    Ash.update!(slice, %{state: :in_progress}, domain: Factory)

    %{project: fixture.project, run_attempt: run_attempt, slice_id: slice.id}
  end

  test "abstained/0 surfaces a parked run with its trust verdict", context do
    abstain_evidence = %{
      integrity_verdict: "suspect",
      calibration_status: :valid,
      baseline_status: :green,
      replay_divergence: :none,
      corpus_pass_rate: 0.95
    }

    gate_context = %{
      project: context.project,
      run_attempt: context.run_attempt,
      run_attempt_id: context.run_attempt.id,
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      canary_suite_version: "canary@1",
      trust_evidence: abstain_evidence
    }

    result = Gate.run!(gate_context, [%{key: "pass", module: PassStage}])
    Finalizer.finalize!(result, gate_context)

    assert [entry] = ParkedQueue.abstained()
    assert entry.run_attempt_id == context.run_attempt.id
    assert entry.slice_id == context.slice_id
    assert entry.band == "abstain"
    assert entry.trust_score["band"] == "abstain"
  end

  test "abstained/0 is empty when nothing has abstained" do
    assert ParkedQueue.abstained() == []
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
