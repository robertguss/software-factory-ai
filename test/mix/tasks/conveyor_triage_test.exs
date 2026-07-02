defmodule Mix.Tasks.Conveyor.TriageTest do
  @moduledoc "uevc.1: the needs-a-human triage queue CLI — reason-typed, least-trusted-first, disposition."
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
    Process.put(:conveyor_triage_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_triage_exit_fun) end)
    :ok
  end

  test "empty queue exits 0 with a clean empty payload" do
    output = capture_io(fn -> Mix.Tasks.Conveyor.Triage.run([]) end)

    assert %{"schema_version" => "conveyor.triage_queue@1", "count" => 0, "parked" => []} =
             Jason.decode!(output)

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "lists parked slices of each reason type with disposition commands, least-trusted-first" do
    weak = abstain_run!(%{calibration_status: :invalid})
    missing = abstain_run!(%{calibration_status: :not_assessed})

    output = capture_io(fn -> Mix.Tasks.Conveyor.Triage.run([]) end)
    decoded = Jason.decode!(output)

    assert decoded["count"] == 2
    by_slice = Map.new(decoded["parked"], &{&1["slice_id"], &1})

    assert by_slice[weak.slice_id]["park_reason"] == "weak_acceptance_tests"
    assert by_slice[missing.slice_id]["park_reason"] == "missing_signal"

    # exact, copy-pasteable disposition commands, inspect first
    commands = by_slice[weak.slice_id]["disposition_commands"]
    assert "mix conveyor.show #{weak.slice_id}" in commands
    assert Enum.any?(commands, &String.contains?(&1, "conveyor.mark_externally_merged"))

    assert by_slice[weak.slice_id]["trust"]["band"] == "abstain"

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "the reject subcommand disposes a parked slice and emits disposition JSON" do
    parked = abstain_run!(%{calibration_status: :invalid})

    output =
      capture_io(fn ->
        Mix.Tasks.Conveyor.Triage.run([
          "reject",
          parked.slice_id,
          "--actor",
          "alice",
          "--note",
          "no"
        ])
      end)

    decoded = Jason.decode!(output)
    assert decoded["schema_version"] == "conveyor.triage_disposition@1"
    assert decoded["disposition"] == "reject"
    assert decoded["slice_id"] == parked.slice_id
    assert decoded["human_approval_id"]

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  # Build a passed-but-abstained (parked) run whose gate evidence yields the given signals.
  defp abstain_run!(evidence_overrides) do
    unique = System.unique_integer([:positive])

    fixture =
      create_artifact_run!(
        blob_root: temp_dir!("triage"),
        project_name: "triage-#{unique}",
        local_path: "/tmp/triage-#{unique}"
      )

    slice = get_by_id!(Slice, fixture.run_attempt.slice_id)

    run_attempt =
      Ash.update!(fixture.run_attempt, %{status: :reviewed, outcome: :none}, domain: Factory)

    Ash.update!(slice, %{state: :in_progress}, domain: Factory)

    evidence =
      Map.merge(
        %{
          integrity_verdict: "trustworthy",
          calibration_status: :valid,
          baseline_status: :green,
          replay_divergence: :none,
          corpus_pass_rate: 0.95
        },
        evidence_overrides
      )

    gate_context = %{
      project: fixture.project,
      run_attempt: run_attempt,
      run_attempt_id: run_attempt.id,
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract",
      canary_suite_version: "canary@1",
      trust_evidence: evidence
    }

    result = Gate.run!(gate_context, [%{key: "pass", module: PassStage}])
    Finalizer.finalize!(result, gate_context)

    %{slice_id: slice.id, run_attempt_id: run_attempt.id}
  end

  defp get_by_id!(resource, id) do
    resource |> Ash.read!(domain: Factory) |> Enum.find(&(&1.id == id))
  end
end
