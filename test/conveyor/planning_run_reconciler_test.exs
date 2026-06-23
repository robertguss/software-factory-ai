defmodule Conveyor.PlanningRunReconcilerTest do
  @moduledoc "U6: interrupted-run detection, crash-vs-reap routing, and the resume-attempt cap."
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Project
  alias Conveyor.Ledger
  alias Conveyor.Planning.RunReconciler

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Recon", local_path: "/tmp/none", default_branch: "main", default_autonomy_level: 3},
        domain: Factory
      )

    %{project: project}
  end

  defp rid, do: "run-#{System.unique_integer([:positive])}"

  defp seed(project, run_id, suffix, type, extra \\ %{}) do
    Ledger.write!(%{
      project_id: project.id,
      idempotency_key: "run:#{run_id}:#{suffix}",
      type: type,
      payload: Map.merge(%{"run_id" => run_id}, extra)
    })
  end

  defp seed_started(project, run_id) do
    seed(project, run_id, "started", "run.started", %{
      "slice_ids" => ["SLICE-001"],
      "work_graph" => %{"slices" => [%{"stable_key" => "SLICE-001"}], "work_dependencies" => []}
    })
  end

  defp recorder, do: fn run_id, _input -> send(self(), {:resumed, run_id}) end

  defp reconcile(opts \\ []) do
    RunReconciler.reconcile!(
      Keyword.merge([resume: recorder(), mark_orphaned_running: false], opts)
    )
  end

  test "an interrupted run (started, no terminal) is resumed", %{project: project} do
    run_id = rid()
    seed_started(project, run_id)

    result = reconcile()

    assert run_id in result.resumed
    assert_received {:resumed, ^run_id}
  end

  test "a completed run (run.finished) is not resumed", %{project: project} do
    run_id = rid()
    seed_started(project, run_id)
    seed(project, run_id, "finished", "run.finished")

    result = reconcile()

    refute run_id in result.resumed
    refute_received {:resumed, ^run_id}
    assert result.complete >= 1
  end

  test "a run-reaped run (run.reaped terminal) parks, not resumes", %{project: project} do
    run_id = rid()
    seed_started(project, run_id)
    seed(project, run_id, "reaped", "run.reaped")

    result = reconcile()

    assert run_id in result.parked
    refute run_id in result.resumed
    refute_received {:resumed, ^run_id}
  end

  test "a per-slice reaped_wall_clock outcome does NOT suppress resume", %{project: project} do
    run_id = rid()
    seed_started(project, run_id)
    # A slice the wall-clock reaper parked — the run continued past it and then crashed.
    seed(project, run_id, "slice:SLICE-001:1", "run.slice_outcome", %{
      "slice_id" => "SLICE-001",
      "sequence" => 1,
      "status" => "parked",
      "gate_result" => "reaped_wall_clock"
    })

    result = reconcile()

    # No run.reaped terminal -> treated as a crash and resumed.
    assert run_id in result.resumed
    assert_received {:resumed, ^run_id}
  end

  test "after K resume attempts the run parks instead of resuming again", %{project: project} do
    run_id = rid()
    seed_started(project, run_id)
    seed(project, run_id, "resumed:0", "run.resumed")
    seed(project, run_id, "resumed:1", "run.resumed")

    result = reconcile(resume_attempt_cap: 2)

    assert run_id in result.parked
    refute run_id in result.resumed
    refute_received {:resumed, ^run_id}
  end

  test "a failing resume is counted as failed, not resumed", %{project: project} do
    run_id = rid()
    seed_started(project, run_id)

    result =
      reconcile(resume: fn _run_id, _input -> raise "boom" end)

    assert run_id in result.failed
    refute run_id in result.resumed
  end
end
