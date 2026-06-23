defmodule Conveyor.PlanningRunLedgerTest do
  @moduledoc """
  U1/U2: SerialDriver commits a durable run-scoped event stream (run.started,
  run.slice_outcome per slice, run.finished/run.reaped terminal) to the append-only
  ledger, so a crashed run can later be reconstructed and resumed (U3/U4).
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Planning.SerialDriver

  defp fixture! do
    project =
      Ash.create!(
        Project,
        %{name: "Ledger Test", local_path: "/tmp/none", default_branch: "main", default_autonomy_level: 3},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Ledger plan",
          intent: "exercise the run ledger",
          source_document: "test",
          normalized_contract: %{"goal" => "test"},
          contract_sha256: "sha256:test",
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Ledger epic", description: "x"}, domain: Factory)

    slices_by_stable_key =
      ["SLICE-001", "SLICE-002"]
      |> Enum.with_index(1)
      |> Map.new(fn {key, position} ->
        slice =
          Ash.create!(
            Slice,
            %{
              epic_id: epic.id,
              title: key,
              position: position,
              risk: "medium",
              autonomy_level: "L2",
              source_refs: [],
              likely_files: [],
              conflict_domains: []
            },
            domain: Factory
          )

        {key, slice}
      end)

    %{project: project, slices_by_stable_key: slices_by_stable_key}
  end

  defp work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [%{"stable_key" => "SLICE-001"}, %{"stable_key" => "SLICE-002"}],
      "work_dependencies" => [%{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"}]
    }
  end

  defp fake_opts(fixture, run_id) do
    [
      run_id: run_id,
      rework: false,
      slices_by_stable_key: fixture.slices_by_stable_key,
      assemble_run_spec: fn key, _g -> %{id: "rs:#{key}", slice_key: key} end,
      create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
      run_slice: fn _at -> %{status: :succeeded, output: %{}} end,
      run_gate: fn _rs, _at, _sr -> %{passed?: true, findings: []} end,
      finalize_gate: fn _g, _rs, at -> %{run_attempt: Map.put(at, :outcome, :accepted)} end,
      advance_workspace_base: fn _rs, _key, _f -> nil end
    ]
  end

  defp events_for(run_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.payload["run_id"] == run_id))
    |> Enum.sort_by(& &1.occurred_at, DateTime)
  end

  test "commits run.started, a run.slice_outcome per slice, and a run.finished terminal" do
    fixture = fixture!()
    run_id = "rl-#{System.unique_integer([:positive])}"

    result =
      SerialDriver.run!(
        %{work_graph: work_graph(), selected_slice_ids: ["SLICE-001", "SLICE-002"]},
        fake_opts(fixture, run_id)
      )

    assert result.status == :passed

    events = events_for(run_id)
    types = Enum.map(events, & &1.type)

    assert "run.started" in types
    assert "run.finished" in types
    refute "run.reaped" in types

    outcomes =
      events
      |> Enum.filter(&(&1.type == "run.slice_outcome"))
      |> Enum.sort_by(& &1.payload["sequence"])

    assert Enum.map(outcomes, & &1.payload["slice_id"]) == ["SLICE-001", "SLICE-002"]
    assert Enum.all?(outcomes, &(&1.payload["status"] == "passed"))
    # run_attempt_outcome atom is stringified for JSON storage (jsonable/1).
    assert Enum.all?(outcomes, &(&1.payload["run_attempt_outcome"] == "accepted"))
    # every run-scoped event carries the same project_id and run_id.
    assert Enum.all?(events, &(&1.project_id == fixture.project.id))
  end

  test "re-running the same run_id dedups the slice-outcome rows (resume idempotency)" do
    fixture = fixture!()
    run_id = "rl-#{System.unique_integer([:positive])}"
    input = %{work_graph: work_graph(), selected_slice_ids: ["SLICE-001", "SLICE-002"]}

    SerialDriver.run!(input, fake_opts(fixture, run_id))
    SerialDriver.run!(input, fake_opts(fixture, run_id))

    outcomes =
      run_id |> events_for() |> Enum.filter(&(&1.type == "run.slice_outcome"))

    # Deterministic key run:{run_id}:slice:{slice_id}:{sequence} -> one row per slice.
    assert length(outcomes) == 2
  end

  test "no project context (map fakes) skips ledger writes entirely" do
    run_id = "rl-#{System.unique_integer([:positive])}"

    SerialDriver.run!(
      %{work_graph: work_graph(), selected_slice_ids: ["SLICE-001"]},
      run_id: run_id,
      rework: false,
      assemble_run_spec: fn key, _g -> %{id: "rs:#{key}", slice_key: key} end,
      create_run_attempt: fn rs -> %{id: "at", run_spec: rs} end,
      run_slice: fn _at -> %{status: :succeeded, output: %{}} end,
      run_gate: fn _rs, _at, _sr -> %{passed?: true, findings: []} end,
      finalize_gate: fn _g, _rs, at -> %{run_attempt: Map.put(at, :outcome, :accepted)} end,
      advance_workspace_base: fn _rs, _key, _f -> nil end
    )

    assert events_for(run_id) == []
  end
end
