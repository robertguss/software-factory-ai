defmodule Conveyor.Planning.WorkGraphBuilderTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Planning.SerialDriver
  alias Conveyor.Planning.WorkGraphBuilder
  alias Conveyor.TaskGraph

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "WGB sample", local_path: "/tmp/wgb", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "WGB plan",
          intent: "Build the work graph from rows.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Epic", description: "Slices."},
        domain: Factory
      )

    %{plan: plan, epic: epic}
  end

  test "builds work_graph@2 with exactly the declared edges (no fabricated chain)", %{
    plan: plan,
    epic: epic
  } do
    a = TaskGraph.create_task(%{epic_id: epic.id, title: "A", source_refs: ["REQ-001"]})
    b = TaskGraph.create_task(%{epic_id: epic.id, title: "B"})
    _c = TaskGraph.create_task(%{epic_id: epic.id, title: "C"})

    # one edge only: A -> B. C is independent.
    TaskGraph.add_dependency(a.id, b.id)

    graph = WorkGraphBuilder.build(plan.id)

    assert graph["schema_version"] == "conveyor.work_graph@2"

    assert Enum.map(graph["slices"], & &1["stable_key"]) == [
             "SLICE-001",
             "SLICE-002",
             "SLICE-003"
           ]

    assert hd(graph["slices"])["requirement_refs"] == ["REQ-001"]

    assert graph["work_dependencies"] == [
             %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"}
           ]
  end

  test "zero edges yields empty work_dependencies (independence preserved)", %{
    plan: plan,
    epic: epic
  } do
    TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
    TaskGraph.create_task(%{epic_id: epic.id, title: "B"})

    graph = WorkGraphBuilder.build(plan.id)

    assert length(graph["slices"]) == 2
    assert graph["work_dependencies"] == []
  end

  test "the built graph drives SerialDriver.run! to a :passed result in topological order", %{
    plan: plan,
    epic: epic
  } do
    a = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
    b = TaskGraph.create_task(%{epic_id: epic.id, title: "B"})
    c = TaskGraph.create_task(%{epic_id: epic.id, title: "C"})

    # chain A -> B -> C, authored out of order to prove the topo sort, not insertion order, wins
    TaskGraph.add_dependency(b.id, c.id)
    TaskGraph.add_dependency(a.id, b.id)

    graph = WorkGraphBuilder.build(plan.id)
    selected = Enum.map(graph["slices"], & &1["stable_key"])

    result =
      SerialDriver.run!(
        %{work_graph: graph, selected_slice_ids: Enum.shuffle(selected)},
        rework: false,
        assemble_run_spec: fn slice_key, _g -> %{id: "rs:#{slice_key}", slice_key: slice_key} end,
        create_run_attempt: fn rs -> %{id: "at:#{rs.slice_key}", run_spec: rs} end,
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{"status" => "passed"}}}
        end,
        run_gate: fn _rs, _attempt, _slice_result -> %{passed?: true, findings: []} end,
        finalize_gate: fn _gate, _rs, attempt ->
          %{run_attempt: Map.put(attempt, :outcome, :accepted)}
        end,
        advance_workspace_base: false
      )

    assert result.status == :passed
    assert result.report["serial_order"] == ["SLICE-001", "SLICE-002", "SLICE-003"]
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
