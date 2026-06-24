defmodule Conveyor.Factory.TaskDependencyTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TaskDependency

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Task graph sample",
          local_path: "/tmp/task-graph-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Task graph plan",
          intent: "Persist task dependency edges.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Task graph epic", description: "Edges."},
        domain: Factory
      )

    %{epic: epic}
  end

  test "creates a directed edge that persists with kind :execution_hard", %{epic: epic} do
    from = slice!(epic, "From", 1, "SLICE-001")
    to = slice!(epic, "To", 2, "SLICE-002")

    edge =
      Ash.create!(
        TaskDependency,
        %{from_slice_id: from.id, to_slice_id: to.id},
        domain: Factory
      )

    assert edge.kind == :execution_hard
    assert edge.from_slice_id == from.id
    assert edge.to_slice_id == to.id

    reloaded = Ash.get!(TaskDependency, edge.id, domain: Factory)
    assert reloaded.kind == :execution_hard
  end

  test "a duplicate (from, to) edge violates the unique edge identity", %{epic: epic} do
    from = slice!(epic, "From", 1, "SLICE-001")
    to = slice!(epic, "To", 2, "SLICE-002")
    attrs = %{from_slice_id: from.id, to_slice_id: to.id}

    Ash.create!(TaskDependency, attrs, domain: Factory)

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(TaskDependency, attrs, domain: Factory)
    end
  end

  test "a self-loop edge is rejected by the DB check constraint", %{epic: epic} do
    slice = slice!(epic, "Solo", 1, "SLICE-001")

    assert_raise Ash.Error.Unknown, fn ->
      Ash.create!(
        TaskDependency,
        %{from_slice_id: slice.id, to_slice_id: slice.id},
        domain: Factory
      )
    end
  end

  test "deleting a slice cascades and removes its edges", %{epic: epic} do
    from = slice!(epic, "From", 1, "SLICE-001")
    to = slice!(epic, "To", 2, "SLICE-002")

    Ash.create!(TaskDependency, %{from_slice_id: from.id, to_slice_id: to.id}, domain: Factory)

    Ash.destroy!(from, domain: Factory)

    assert Ash.read!(TaskDependency, domain: Factory) == []
  end

  test "two slices in one epic with the same stable_key violate the identity", %{epic: epic} do
    slice!(epic, "First", 1, "SLICE-001")

    assert_raise Ash.Error.Invalid, fn ->
      slice!(epic, "Second", 2, "SLICE-001")
    end
  end

  defp slice!(epic, title, position, stable_key) do
    Ash.create!(
      Slice,
      %{epic_id: epic.id, title: title, position: position, stable_key: stable_key},
      domain: Factory
    )
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
