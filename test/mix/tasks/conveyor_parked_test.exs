defmodule Mix.Tasks.Conveyor.ParkedTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  import Conveyor.FactoryFixtures

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer

  defmodule PassStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts), do: %{status: :passed, evidence_refs: ["evidence.json"]}
  end

  setup do
    test_pid = self()
    Process.put(:conveyor_parked_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_parked_exit_fun) end)
    :ok
  end

  test "prints an empty queue when nothing has abstained" do
    output = capture_io(fn -> Mix.Tasks.Conveyor.Parked.run([]) end)

    assert %{"schema_version" => "conveyor.parked_queue@1", "count" => 0, "abstained" => []} =
             Jason.decode!(output)

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "lists an abstained run with its trust band" do
    fixture = create_artifact_run!(blob_root: temp_dir!("parked-task"))
    slice = get_by_id!(Slice, fixture.run_attempt.slice_id)

    run_attempt =
      Ash.update!(fixture.run_attempt, %{status: :reviewed, outcome: :none}, domain: Factory)

    Ash.update!(slice, %{state: :in_progress}, domain: Factory)

    gate_context = %{
      project: fixture.project,
      run_attempt: run_attempt,
      run_attempt_id: run_attempt.id,
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      canary_suite_version: "canary@1",
      trust_evidence: %{
        integrity_verdict: "suspect",
        calibration_status: :valid,
        baseline_status: :green,
        replay_divergence: :none,
        corpus_pass_rate: 0.95
      }
    }

    result = Gate.run!(gate_context, [%{key: "pass", module: PassStage}])
    Finalizer.finalize!(result, gate_context)

    output = capture_io(fn -> Mix.Tasks.Conveyor.Parked.run([]) end)
    decoded = Jason.decode!(output)

    assert decoded["count"] == 1
    assert [entry] = decoded["abstained"]
    assert entry["run_attempt_id"] == run_attempt.id
    assert entry["slice_id"] == slice.id
    assert entry["band"] == "abstain"

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
