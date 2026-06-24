defmodule Conveyor.TaskGraph do
  @moduledoc """
  The Ash-backed core for authoring and querying the DB-native task graph (U2).

  All CLI verbs and the run path call into this module. Operations are plain functions over
  `Ash.{create!,read!,update!}` (no Ash code interface, per KTD4). This file covers the graph
  operations — task CRUD, dependency edges, readiness, and approval; contract authoring,
  `compile_contract`, and `lock_task` build on top of these.
  """

  require Ash.Query

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.PlanAudit
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TaskDependency
  alias Conveyor.Planning.ContractBuilder
  alias Conveyor.Planning.RunSpecAssembler
  alias Conveyor.Readiness
  alias Conveyor.Repo

  @done_states [:done, :integrated]

  @doc """
  Create a task (`Slice`) under an epic, auto-assigning `position` and the KTD7 `stable_key`
  (`SLICE-NNN`, 1-based per-epic position zero-padded to 3 digits, starting `SLICE-001`).

  Position and key are computed inside a transaction; the `:unique_epic_stable_key` /
  `:unique_epic_position` identities are the backstop, so concurrent creates fail loudly rather
  than colliding.
  """
  def create_task(attrs) when is_map(attrs) do
    epic_id = Map.fetch!(attrs, :epic_id)

    {:ok, {slice, notifications}} =
      Repo.transaction(fn ->
        position = next_position(epic_id)

        attrs
        |> Map.put(:position, position)
        |> Map.put(:stable_key, stable_key(position))
        |> create_slice!()
      end)

    # `Ash.create!` inside a transaction defers its notifications; emit them after commit so
    # subscribers fire and Ash's `:missed_notifications` warning stays quiet (mirrors
    # `Conveyor.PlanLifecycle`).
    Ash.Notifier.notify(notifications)
    slice
  end

  @doc "Update a task's mutable authoring attributes."
  def update_task(slice_id, attrs) when is_map(attrs) do
    slice_id
    |> get_task!()
    |> Ash.update!(attrs, domain: Factory)
  end

  @doc "Fetch one task by id."
  def show_task(slice_id), do: get_task!(slice_id)

  @doc "List an epic's tasks in position order."
  def list_tasks(epic_id) do
    Slice
    |> Ash.Query.filter(epic_id == ^epic_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(domain: Factory)
  end

  @doc """
  Add an `:execution_hard` edge `from -> to` (meaning `to` depends on `from`).

  Validates both tasks exist and share an epic, and rejects self-loops and cycles before the
  insert; the DB unique-edge identity and self-loop check constraint are the backstop.
  """
  def add_dependency(from_slice_id, to_slice_id) do
    from = fetch_task(from_slice_id) || raise ArgumentError, "unknown task: #{from_slice_id}"
    to = fetch_task(to_slice_id) || raise ArgumentError, "unknown task: #{to_slice_id}"

    cond do
      from.id == to.id ->
        raise ArgumentError, "a task cannot depend on itself"

      from.epic_id != to.epic_id ->
        raise ArgumentError, "dependencies must link tasks in the same epic"

      creates_cycle?(from.id, to.id) ->
        raise ArgumentError, "dependency would introduce a cycle"

      true ->
        Ash.create!(
          TaskDependency,
          %{from_slice_id: from.id, to_slice_id: to.id},
          domain: Factory
        )
    end
  end

  @doc "Remove the `from -> to` edge if present. Returns `:ok`."
  def remove_dependency(from_slice_id, to_slice_id) do
    TaskDependency
    |> Ash.Query.filter(from_slice_id == ^from_slice_id and to_slice_id == ^to_slice_id)
    |> Ash.read!(domain: Factory)
    |> Enum.each(&Ash.destroy!(&1, domain: Factory))

    :ok
  end

  @doc """
  Tasks ready to run: every incoming `execution_hard` predecessor is satisfied (the predecessor
  `Slice` has reached a terminal-success state, `:done`/`:integrated`). Roots and independent
  tasks are always ready; already-finished tasks are excluded.
  """
  def ready_tasks(epic_id) do
    slices = list_tasks(epic_id)
    edges = edges_for(slices)
    done = MapSet.new(for s <- slices, s.state in @done_states, do: s.id)

    Enum.filter(slices, fn slice ->
      slice.state not in @done_states and predecessors_satisfied?(slice.id, edges, done)
    end)
  end

  @doc """
  Author a task's acceptance criteria (KTD8). `criteria` is a list of maps in the conveyor.plan@1
  acceptance shape (`id`/`key`, `text`, `requirement_refs`, `required_test_refs`, + optional
  falsifier fields). Stored on the `Slice` (the source); `compile_contract` aggregates these into
  `Plan.normalized_contract`. Writes the source location, never `AgentBrief` (the materialized view).
  """
  def set_acceptance(slice_id, criteria) when is_list(criteria) do
    slice_id
    |> get_task!()
    |> Ash.update!(%{acceptance_criteria: criteria}, domain: Factory)
  end

  @doc """
  The vetted/locked step (KTD3): produce a gate-valid, `:ready` contract for a task by delegating
  to the existing, deterministic materializer — no hand-rolled digests, no run-path fork.

  On the first locked task of a plan it compiles the plan's `normalized_contract` from rows
  (`ContractBuilder`), records a ready `PlanAudit`, and advances the plan `:draft -> :handoff_ready`
  (after which the contract is frozen). For every task it then materializes the
  `AgentBrief`/`TestPack`/`ContractLock` via `RunSpecAssembler.materialize_contract_for_slice!` and
  asserts `Readiness.check == :ready`, raising with the readiness findings otherwise. Authoring
  must be complete before the first lock (compile snapshots all tasks' acceptance).
  """
  def lock_task(slice_id) do
    slice = get_task!(slice_id)
    plan = plan_for_slice(slice)

    if plan.status == :draft do
      ContractBuilder.compile_contract(plan.id)
      ensure_ready_audit!(plan)
      advance_to_handoff_ready!(plan)
    end

    RunSpecAssembler.materialize_contract_for_slice!(slice)

    # Verify gate-readiness without advancing state — `:approved` (KTD6) stays the final human
    # transition before a run; lock leaves the task `:drafted`.
    case Readiness.check(slice, mark_ready?: false) do
      %{status: :ready} ->
        get_task!(slice_id)

      %{findings: findings} ->
        raise ArgumentError,
              "lock_task: #{slice.stable_key} is not gate-ready: #{inspect(findings)}"
    end
  end

  @doc "Run a task's `:drafted -> :approved` transition."
  def approve_task(slice_id) do
    slice_id
    |> get_task!()
    |> Ash.update!(%{}, action: :approve, domain: Factory)
  end

  # -- internals --------------------------------------------------------------

  defp create_slice!(attrs),
    do: Ash.create!(Slice, attrs, domain: Factory, return_notifications?: true)

  defp next_position(epic_id) do
    Slice
    |> Ash.Query.filter(epic_id == ^epic_id)
    |> Ash.read!(domain: Factory)
    |> Enum.map(& &1.position)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp stable_key(position),
    do: "SLICE-" <> String.pad_leading(Integer.to_string(position), 3, "0")

  defp get_task!(slice_id), do: Ash.get!(Slice, slice_id, domain: Factory)

  defp plan_for_slice(%Slice{} = slice) do
    epic = Ash.get!(Epic, slice.epic_id, domain: Factory)
    Ash.get!(Plan, epic.plan_id, domain: Factory)
  end

  defp ensure_ready_audit!(%Plan{} = plan) do
    PlanAudit
    |> Ash.Query.filter(plan_id == ^plan.id and decision == :ready)
    |> Ash.read!(domain: Factory)
    |> case do
      [] ->
        Ash.create!(PlanAudit, %{plan_id: plan.id, score: 100, decision: :ready}, domain: Factory)

      [audit | _] ->
        audit
    end
  end

  defp advance_to_handoff_ready!(%Plan{} = plan) do
    plan
    |> Ash.update!(%{status: :audited}, domain: Factory)
    |> Ash.update!(%{status: :handoff_ready}, domain: Factory)
  end

  defp fetch_task(slice_id) do
    case Ash.get(Slice, slice_id, domain: Factory) do
      {:ok, slice} -> slice
      {:error, _} -> nil
    end
  end

  defp edges_for(slices) do
    ids = MapSet.new(slices, & &1.id)

    TaskDependency
    |> Ash.read!(domain: Factory)
    |> Enum.filter(
      &(MapSet.member?(ids, &1.from_slice_id) or MapSet.member?(ids, &1.to_slice_id))
    )
  end

  defp predecessors_satisfied?(slice_id, edges, done) do
    edges
    |> Enum.filter(&(&1.to_slice_id == slice_id))
    |> Enum.all?(&MapSet.member?(done, &1.from_slice_id))
  end

  # Adding `from -> to` creates a cycle iff `to` can already reach `from` via existing edges.
  defp creates_cycle?(from_id, to_id) do
    edges = Ash.read!(TaskDependency, domain: Factory)
    reachable?(to_id, from_id, edges, MapSet.new())
  end

  defp reachable?(current, target, _edges, _seen) when current == target, do: true

  defp reachable?(current, target, edges, seen) do
    if MapSet.member?(seen, current) do
      false
    else
      seen = MapSet.put(seen, current)

      edges
      |> Enum.filter(&(&1.from_slice_id == current))
      |> Enum.any?(&reachable?(&1.to_slice_id, target, edges, seen))
    end
  end
end
