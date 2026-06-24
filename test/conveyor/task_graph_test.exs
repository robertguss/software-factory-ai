defmodule Conveyor.TaskGraphTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.TaskGraph

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "TaskGraph sample", local_path: "/tmp/task-graph-core", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "TaskGraph plan",
          intent: "Author the graph via the core.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "TaskGraph epic", description: "Graph."},
        domain: Factory
      )

    %{epic: epic}
  end

  describe "create_task/1" do
    test "assigns sequential SLICE-NNN stable keys and positions", %{epic: epic} do
      one = TaskGraph.create_task(%{epic_id: epic.id, title: "First"})
      two = TaskGraph.create_task(%{epic_id: epic.id, title: "Second"})

      assert one.stable_key == "SLICE-001"
      assert one.position == 1
      assert two.stable_key == "SLICE-002"
      assert two.position == 2
      assert one.state == :drafted
    end

    test "accepts authoring attributes", %{epic: epic} do
      task =
        TaskGraph.create_task(%{
          epic_id: epic.id,
          title: "Rich",
          likely_files: ["lib/a.ex"],
          conflict_domains: ["schema"],
          source_refs: ["REQ-001"],
          autonomy_level: "L2"
        })

      assert task.likely_files == ["lib/a.ex"]
      assert task.conflict_domains == ["schema"]
      assert task.source_refs == ["REQ-001"]
      assert task.autonomy_level == "L2"
    end
  end

  describe "update_task/2, show_task/1, list_tasks/1" do
    test "update mutates, show fetches, list returns in position order", %{epic: epic} do
      a = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
      b = TaskGraph.create_task(%{epic_id: epic.id, title: "B"})

      updated = TaskGraph.update_task(a.id, %{title: "A2"})
      assert updated.title == "A2"
      assert TaskGraph.show_task(a.id).title == "A2"

      assert TaskGraph.list_tasks(epic.id) |> Enum.map(& &1.id) == [a.id, b.id]
    end
  end

  describe "add_dependency/2 and remove_dependency/2" do
    test "links two tasks in the same epic", %{epic: epic} do
      from = TaskGraph.create_task(%{epic_id: epic.id, title: "From"})
      to = TaskGraph.create_task(%{epic_id: epic.id, title: "To"})

      edge = TaskGraph.add_dependency(from.id, to.id)
      assert edge.from_slice_id == from.id
      assert edge.to_slice_id == to.id
      assert edge.kind == :execution_hard

      :ok = TaskGraph.remove_dependency(from.id, to.id)

      assert TaskGraph.ready_tasks(epic.id) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([from.id, to.id])
    end

    test "rejects a self-loop", %{epic: epic} do
      task = TaskGraph.create_task(%{epic_id: epic.id, title: "Solo"})

      assert_raise ArgumentError, ~r/itself/, fn ->
        TaskGraph.add_dependency(task.id, task.id)
      end
    end

    test "rejects a cycle (A->B then B->A)", %{epic: epic} do
      a = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
      b = TaskGraph.create_task(%{epic_id: epic.id, title: "B"})

      TaskGraph.add_dependency(a.id, b.id)

      assert_raise ArgumentError, ~r/cycle/, fn ->
        TaskGraph.add_dependency(b.id, a.id)
      end
    end

    test "rejects an unknown task ref", %{epic: epic} do
      task = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})

      assert_raise ArgumentError, ~r/unknown task/, fn ->
        TaskGraph.add_dependency(task.id, Ecto.UUID.generate())
      end
    end

    test "rejects a cross-epic dependency", %{epic: epic} do
      plan = Ash.get!(Plan, Ash.get!(Epic, epic.id, domain: Factory).plan_id, domain: Factory)

      other_epic =
        Ash.create!(Epic, %{plan_id: plan.id, title: "Other", description: "Other."},
          domain: Factory
        )

      here = TaskGraph.create_task(%{epic_id: epic.id, title: "Here"})
      there = TaskGraph.create_task(%{epic_id: other_epic.id, title: "There"})

      assert_raise ArgumentError, ~r/same epic/, fn ->
        TaskGraph.add_dependency(here.id, there.id)
      end
    end
  end

  describe "ready_tasks/1" do
    test "roots and independents are ready; dependents wait for predecessors", %{epic: epic} do
      root = TaskGraph.create_task(%{epic_id: epic.id, title: "Root"})
      dependent = TaskGraph.create_task(%{epic_id: epic.id, title: "Dependent"})
      independent = TaskGraph.create_task(%{epic_id: epic.id, title: "Independent"})

      # dependent depends on root (edge root -> dependent)
      TaskGraph.add_dependency(root.id, dependent.id)

      ready_ids = TaskGraph.ready_tasks(epic.id) |> Enum.map(& &1.id) |> Enum.sort()
      assert ready_ids == Enum.sort([root.id, independent.id])

      # satisfy the predecessor
      complete!(root)

      ready_ids = TaskGraph.ready_tasks(epic.id) |> Enum.map(& &1.id) |> Enum.sort()
      assert dependent.id in ready_ids
      refute root.id in ready_ids
    end
  end

  describe "set_acceptance/2" do
    test "stores acceptance criteria on the task and round-trips", %{epic: epic} do
      task = TaskGraph.create_task(%{epic_id: epic.id, title: "A", source_refs: ["REQ-001"]})

      criteria = [
        %{
          "id" => "AC-001",
          "text" => "Loading the fixture corpus yields stable counts.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["tests/test_loader.py::test_counts"]
        }
      ]

      updated = TaskGraph.set_acceptance(task.id, criteria)
      assert [%{"id" => "AC-001"} = stored] = updated.acceptance_criteria
      assert stored["requirement_refs"] == ["REQ-001"]

      assert TaskGraph.show_task(task.id).acceptance_criteria |> hd() |> Map.get("text") ==
               "Loading the fixture corpus yields stable counts."
    end
  end

  describe "approve_task/1" do
    test "moves a task :drafted -> :approved", %{epic: epic} do
      task = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
      approved = TaskGraph.approve_task(task.id)
      assert approved.state == :approved
    end

    test "raises from a non-:drafted state", %{epic: epic} do
      task = TaskGraph.create_task(%{epic_id: epic.id, title: "A"})
      TaskGraph.approve_task(task.id)

      assert_raise Ash.Error.Invalid, fn ->
        TaskGraph.approve_task(task.id)
      end
    end
  end

  # Drive a slice to :done through its real state-machine transitions.
  defp complete!(slice) do
    slice
    |> transition(:approve)
    |> transition(:mark_ready)
    |> transition(:start)
    |> transition(:gate)
    |> transition(:integrate)
    |> transition(:complete)
  end

  defp transition(slice, action), do: Ash.update!(slice, %{}, action: action, domain: Factory)

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
