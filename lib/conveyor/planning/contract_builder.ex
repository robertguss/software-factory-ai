defmodule Conveyor.Planning.ContractBuilder do
  @moduledoc """
  Compiles the DB-native task-graph rows into the `conveyor.plan@1` `Plan.normalized_contract`
  (KTD8). Sibling of `WorkGraphBuilder`: relational rows are the source of truth, this map is a
  deterministic build artifact — never hand-edited, regenerated at `lock` time.

  Minimal-runnable scope: `goal`, `project`, `slices`, and `acceptance_criteria` come from rows;
  the optional `non_goals`/`requirements`/`decisions`/`verification_commands` are emitted as empty
  arrays (the assembler defaults them at runtime). Authoring verbs for those fields layer on later.
  """

  require Ash.Query

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.PlanContract

  @schema_version "conveyor.plan@1"

  @doc """
  Compile a plan's rows into its `normalized_contract`, persist `normalized_contract` +
  `contract_sha256` on the `Plan`, and return the updated plan.

  Only valid while the plan is `:draft` — the contract is frozen once the plan leaves draft (the
  `plans_freeze_contract_after_draft` trigger). `lock_task` calls this before transitioning the
  plan to `:handoff_ready`.
  """
  def compile_contract(plan_id) do
    plan = Ash.get!(Plan, plan_id, domain: Factory)
    contract = build(plan)

    Ash.update!(
      plan,
      %{normalized_contract: contract, contract_sha256: PlanContract.contract_sha256(contract)},
      domain: Factory
    )
  end

  @doc "Build the normalized contract map for a plan from its rows (pure; no persistence)."
  def build(%Plan{} = plan) do
    project = Ash.get!(Project, plan.project_id, domain: Factory)
    slices = slices_for_plan(plan.id)

    %{
      "schema_version" => @schema_version,
      "project" => %{"key" => project.name, "base_ref" => project.default_branch},
      "goal" => plan.intent,
      "non_goals" => [],
      "requirements" => [],
      "acceptance_criteria" => acceptance_criteria(slices),
      "verification_commands" => [],
      "decisions" => [],
      "slices" => Enum.map(slices, &slice_entry/1)
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
      "key" => slice.stable_key,
      "title" => slice.title,
      "requirement_refs" => slice.source_refs,
      "likely_files" => slice.likely_files,
      "conflict_domains" => slice.conflict_domains,
      "autonomy_ceiling" => slice.autonomy_level
    }
  end

  defp acceptance_criteria(slices) do
    slices
    |> Enum.flat_map(& &1.acceptance_criteria)
    |> Enum.map(&stringify/1)
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
