defmodule Conveyor.Planning.WorkGraphBuilder do
  @moduledoc """
  Compiles a plan's persisted rows into the `conveyor.work_graph@2` map `SerialDriver` consumes
  (R3, R6, KTD5). Sibling of `ContractBuilder`: rows are the source of truth, this map is a
  deterministic projection.

  Reproduces the exact shape `PlanRunner` built in-memory — `slices` from `Slice` rows,
  `work_dependencies` from `TaskDependency` rows resolved to stable keys — so `SerialDriver`, the
  7-stage gate, and the ledger run unchanged. **No linear-chain fallback**: absent edges yield an
  empty `work_dependencies` (genuinely-independent tasks), retiring the fabricated chain (gap 4).
  """

  require Ash.Query

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TaskDependency

  @schema_version "conveyor.work_graph@2"

  @doc "Build the `conveyor.work_graph@2` map for a plan (by id or struct) from its rows."
  def build(plan_id) when is_binary(plan_id) do
    plan_id |> then(&Ash.get!(Plan, &1, domain: Factory)) |> build()
  end

  def build(%Plan{} = plan) do
    slices = slices_for_plan(plan.id)

    %{
      "schema_version" => @schema_version,
      "slices" => Enum.map(slices, &slice_entry/1),
      "work_dependencies" => work_dependencies(slices)
    }
  end

  defp slices_for_plan(plan_id) do
    epic_ids =
      Epic
      |> Ash.Query.filter(plan_id == ^plan_id)
      |> Ash.read!(domain: Factory)
      |> Enum.map(& &1.id)

    Slice
    |> Ash.Query.filter(epic_id in ^epic_ids)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(domain: Factory)
  end

  defp slice_entry(%Slice{} = slice) do
    %{
      "stable_key" => slice.stable_key,
      "title" => slice.title,
      "requirement_refs" => slice.source_refs,
      "likely_files" => slice.likely_files,
      "conflict_domains" => slice.conflict_domains
    }
  end

  defp work_dependencies(slices) do
    key_by_id = Map.new(slices, &{&1.id, &1.stable_key})
    ids = MapSet.new(Map.keys(key_by_id))

    TaskDependency
    |> Ash.read!(domain: Factory)
    |> Enum.filter(
      &(MapSet.member?(ids, &1.from_slice_id) and MapSet.member?(ids, &1.to_slice_id))
    )
    |> Enum.map(fn edge ->
      %{
        "from" => Map.fetch!(key_by_id, edge.from_slice_id),
        "to" => Map.fetch!(key_by_id, edge.to_slice_id),
        "kind" => to_string(edge.kind)
      }
    end)
    |> Enum.sort_by(&{&1["from"], &1["to"]})
  end
end
