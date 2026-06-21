defmodule Mix.Tasks.Conveyor.ShowTrustTest do
  @moduledoc "ADR-23: `mix conveyor.show` surfaces the slice's trust verdict (drill-down from the parked queue)."
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO
  import Conveyor.FactoryFixtures

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
    Process.put(:conveyor_show_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_show_exit_fun) end)
    :ok
  end

  test "show reports the trust verdict and outcome for an abstained slice" do
    fixture = create_artifact_run!(blob_root: temp_dir!("show-trust"))
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

    output = capture_io(fn -> Mix.Tasks.Conveyor.Show.run([slice.id]) end)
    decoded = Jason.decode!(output)

    assert decoded["latest_run_attempt_outcome"] == "abstained"
    assert decoded["trust_verdict"]["band"] == "abstain"
    assert_received {:exit_code, 0}
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
