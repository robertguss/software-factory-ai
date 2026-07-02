defmodule Conveyor.Triage.DispositionTest do
  @moduledoc "uevc.2: triage disposition engine — effect + evidence + ledger event + exactly-once."
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer
  alias Conveyor.Triage.Disposition

  defmodule PassStage do
    @behaviour Conveyor.Gate.Stage
    @impl true
    def run(_context, _opts), do: %{status: :passed, evidence_refs: ["evidence.json"]}
  end

  test "reject records a rejected approval + ledger event and leaves the slice parked" do
    slice_id = park_slice!()

    assert {:ok, result} = Disposition.reject(slice_id, actor: "alice", note: "wrong approach")
    assert result.terminal_state == :parked
    assert slice_state(slice_id) == :parked

    assert [approval] = approvals(slice_id)
    assert approval.decision == :rejected
    assert approval.actor == "alice"
    assert approval.rationale == "wrong approach"
    assert event_count(slice_id, "reject") == 1
  end

  test "rework routes the slice to :needs_rework with the operator note" do
    slice_id = park_slice!()

    assert {:ok, result} = Disposition.rework(slice_id, actor: "bob", note: "add edge-case test")
    assert result.terminal_state == :needs_rework
    assert slice_state(slice_id) == :needs_rework

    assert [approval] = approvals(slice_id)
    assert approval.decision == :reworked
    assert approval.rationale == "add edge-case test"
    assert event_count(slice_id, "rework") == 1
  end

  test "approve applies the captured patch (seam) and integrates the slice" do
    slice_id = park_slice!()

    assert {:ok, result} =
             Disposition.approve(slice_id, actor: "carol", apply_patch: fn _s, _o -> :ok end)

    assert result.terminal_state == :integrated
    assert slice_state(slice_id) == :integrated
    assert [%{decision: :approved}] = approvals(slice_id)
    assert event_count(slice_id, "approve") == 1
  end

  test "approve fails honestly on a patch conflict — no transition, no evidence, no event" do
    slice_id = park_slice!()

    assert {:error, {:patch_conflict, :conflict}} =
             Disposition.approve(slice_id,
               actor: "carol",
               apply_patch: fn _s, _o -> {:error, :conflict} end
             )

    assert slice_state(slice_id) == :parked
    assert approvals(slice_id) == []
    assert event_count(slice_id, "approve") == 0
  end

  test "a repeated disposition is an exactly-once no-op (crash-safe reconcile)" do
    slice_id = park_slice!()

    assert {:ok, %{terminal_state: :parked}} = Disposition.reject(slice_id, actor: "alice")
    assert {:ok, %{status: :already_disposed}} = Disposition.reject(slice_id, actor: "alice")

    # exactly one evidence row and one ledger event survive the replay
    assert length(approvals(slice_id)) == 1
    assert event_count(slice_id, "reject") == 1
  end

  # --- helpers ---------------------------------------------------------------

  defp park_slice! do
    unique = System.unique_integer([:positive])

    fixture =
      create_artifact_run!(
        blob_root: temp_dir!("disp"),
        project_name: "disp-#{unique}",
        local_path: "/tmp/disp-#{unique}"
      )

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
        integrity_verdict: "trustworthy",
        calibration_status: :invalid,
        baseline_status: :green,
        replay_divergence: :none,
        corpus_pass_rate: 0.95
      }
    }

    result = Gate.run!(gate_context, [%{key: "pass", module: PassStage}])
    Finalizer.finalize!(result, gate_context)

    slice.id
  end

  defp slice_state(slice_id), do: get_by_id!(Slice, slice_id).state

  defp approvals(slice_id) do
    HumanApproval
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id and &1.approval_type == "triage_disposition"))
  end

  defp event_count(slice_id, type) do
    key = "triage.disposition:#{slice_id}:#{type}"

    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.count(&(&1.idempotency_key == key))
  end

  defp get_by_id!(resource, id) do
    resource |> Ash.read!(domain: Factory) |> Enum.find(&(&1.id == id))
  end
end
