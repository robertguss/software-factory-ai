defmodule ConveyorWeb.ParkedQueueLiveTest do
  use ConveyorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer

  defmodule PassStage do
    @behaviour Conveyor.Gate.Stage
    @impl true
    def run(_context, _opts), do: %{status: :passed, evidence_refs: ["e.json"]}
  end

  test "shows the empty-queue message when nothing has abstained", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/parked")

    assert html =~ "Needs a human"
    assert html =~ "Nothing parked"
  end

  test "lists an abstained run with its band", %{conn: conn} do
    run_attempt = abstain_one!()

    {:ok, _view, html} = live(conn, "/parked")

    assert html =~ "parked-#{run_attempt.id}"
    assert html =~ "abstain"
    assert html =~ "(1)"
  end

  # Drive a real low-trust finalize so a run abstains and parks.
  defp abstain_one! do
    fixture = create_artifact_run!(blob_root: temp_dir!("parked-live"))
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
    run_attempt
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
