defmodule Conveyor.ParkedQueueTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.GateResult
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

  test "abstained/0 orders multiple parked runs least-trusted first" do
    create_run_with_ledger!(
      slices: [
        abstained_slice(0.8),
        abstained_slice(0.2),
        abstained_slice(0.5)
      ]
    )

    entries = ParkedQueue.abstained()

    # Headline contract: most urgent (lowest trust) on top, regardless of insert order.
    assert Enum.map(entries, & &1.score) == [0.2, 0.5, 0.8]
  end

  test "abstained/0 places parked runs with no trust verdict after scored ones" do
    create_run_with_ledger!(
      slices: [
        abstained_slice(0.5),
        # outcome :abstained but no gate -> no GateResult -> no trust verdict.
        %{outcome: :abstained}
      ]
    )

    entries = ParkedQueue.abstained()

    # score_key(nil) = {1, 0.0} sorts the verdict-less attempt last.
    assert Enum.map(entries, & &1.score) == [0.5, nil]
  end

  test "abstained/0 dedups multiple gate verdicts per attempt deterministically" do
    %{run_attempts: run_attempts} =
      create_run_with_ledger!(slices: [abstained_slice(0.3)])

    [run_attempt] = run_attempts |> Map.values() |> List.flatten()

    # A second, competing trust verdict on the SAME attempt.
    create_gate_result!(run_attempt.id, 0.7)

    # The deterministic winner is the highest-id verdict (id is the stable key;
    # GateResult has no timestamp). Compute it from the persisted rows so the test
    # tracks the implementation's rule rather than a hard-coded score.
    expected_score =
      GateResult
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
      |> Enum.max_by(& &1.id)
      |> then(& &1.trust_score["score"])

    assert [entry] = ParkedQueue.abstained()
    assert entry.score == expected_score
    # Identical across repeated calls — the survivor no longer depends on read order.
    assert ParkedQueue.abstained() == ParkedQueue.abstained()
  end

  defp abstained_slice(score) do
    %{
      outcome: :abstained,
      gate: %{passed: true, trust_score: %{"band" => "abstain", "score" => score}}
    }
  end

  defp create_gate_result!(run_attempt_id, score) do
    Ash.create!(
      GateResult,
      %{
        run_attempt_id: run_attempt_id,
        passed: true,
        stages: [],
        trust_score: %{"band" => "abstain", "score" => score},
        gate_version: "gate@1",
        gate_code_sha256: "sha256:gate-code",
        policy_sha256: "sha256:policy",
        contract_lock_sha256: "sha256:contract-lock",
        canary_suite_version: "canary@1"
      },
      domain: Factory
    )
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
