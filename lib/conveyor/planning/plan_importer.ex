defmodule Conveyor.Planning.PlanImporter do
  @moduledoc """
  One-time migration: read a legacy `conveyor.plan@1` YAML contract and materialize it into the
  DB-native rows (U7). Writes the same rows the `conveyor.task.*` CLI authors — Project / Plan /
  Epic / Slice + `TaskDependency` edges — so a migrated plan and a CLI-authored plan are the same
  shape downstream.

  Dependencies are imported **as declared** in the YAML: a plan that declared none yields zero
  edges (genuinely-independent tasks), retiring the linear-chain fabrication (gap 4) rather than
  reproducing it. The imported plan carries the YAML's `normalized_contract`, so the run path
  materializes acceptance from it exactly as before — only the graph is now DB-sourced.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, Plan, Project, Slice, TaskDependency}
  alias Conveyor.PlanContract

  @doc "Import a YAML plan file at `path` into DB rows. Returns the created project/plan/epic/slices."
  def import!(path, opts \\ []) do
    {:ok, result} = PlanContract.load(path)
    import_result!(result, opts)
  end

  @doc "Import an already-loaded `PlanContract.Result` into DB rows."
  def import_result!(%PlanContract.Result{} = result, opts) do
    contract = result.contract
    workspace_path = Keyword.get(opts, :workspace_path) || Path.dirname(result.source_path)

    project = create_project!(contract, workspace_path)
    plan = create_plan!(project, result)
    epic = create_epic!(plan, contract)
    slices_by_stable_key = create_slices!(epic, contract)
    create_edges!(slices_by_stable_key, contract)

    %{
      project: project,
      plan: plan,
      epic: epic,
      slices_by_stable_key: slices_by_stable_key
    }
  end

  defp create_project!(contract, workspace_path) do
    project = Map.get(contract, "project", %{})
    default_autonomy_level = max_autonomy_level(contract)

    if existing = existing_project(workspace_path) do
      ensure_project_autonomy!(existing, default_autonomy_level)
    else
      Ash.create!(
        Project,
        %{
          name: Map.get(project, "key", "conveyor-plan"),
          local_path: workspace_path,
          default_branch: Map.get(project, "base_ref", "main"),
          default_autonomy_level: default_autonomy_level
        },
        domain: Factory
      )
    end
  end

  defp existing_project(workspace_path) do
    Project |> Ash.read!(domain: Factory) |> Enum.find(&(&1.local_path == workspace_path))
  end

  defp ensure_project_autonomy!(project, default_autonomy_level) do
    if project.default_autonomy_level < default_autonomy_level do
      Ash.update!(project, %{default_autonomy_level: default_autonomy_level}, domain: Factory)
    else
      project
    end
  end

  defp max_autonomy_level(contract) do
    contract
    |> Map.get("slices", [])
    |> Enum.map(&autonomy_level(Map.get(&1, "autonomy_ceiling")))
    |> Enum.max(fn -> 1 end)
  end

  defp autonomy_level("L" <> level), do: parse_positive_integer(level)
  defp autonomy_level(level) when is_integer(level) and level > 0, do: level
  defp autonomy_level(_unknown), do: 1

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _unknown -> 1
    end
  end

  defp create_plan!(project, contract_result) do
    Ash.create!(
      Plan,
      %{
        project_id: project.id,
        title: Map.get(contract_result.contract, "goal", "Conveyor plan"),
        intent: Map.fetch!(contract_result.contract, "goal"),
        source_document: contract_result.source_path,
        normalized_contract: contract_result.contract,
        contract_sha256: contract_result.contract_sha256,
        status: :handoff_ready
      },
      domain: Factory
    )
  end

  defp create_epic!(plan, contract) do
    Ash.create!(
      Epic,
      %{
        plan_id: plan.id,
        title: Map.get(contract, "goal", "Conveyor plan"),
        description: "Imported Conveyor plan for #{plan.source_document}"
      },
      domain: Factory
    )
  end

  defp create_slices!(epic, contract) do
    contract
    |> Map.fetch!("slices")
    |> Enum.with_index(1)
    |> Map.new(fn {slice_contract, position} ->
      slice =
        Ash.create!(
          Slice,
          %{
            epic_id: epic.id,
            title: Map.fetch!(slice_contract, "title"),
            stable_key: Map.fetch!(slice_contract, "key"),
            position: position,
            risk: "medium",
            autonomy_level: Map.get(slice_contract, "autonomy_ceiling", "L1"),
            source_refs: Map.get(slice_contract, "requirement_refs", []),
            likely_files: Map.get(slice_contract, "likely_files", []),
            conflict_domains: Map.get(slice_contract, "conflict_domains", [])
          },
          domain: Factory
        )

      {Map.fetch!(slice_contract, "key"), slice}
    end)
  end

  defp create_edges!(slices_by_stable_key, contract) do
    contract
    |> Map.get("work_dependencies", [])
    |> Enum.each(fn edge ->
      from = Map.fetch!(slices_by_stable_key, Map.fetch!(edge, "from"))
      to = Map.fetch!(slices_by_stable_key, Map.fetch!(edge, "to"))
      kind = edge |> Map.get("kind", "execution_hard") |> String.to_existing_atom()

      Ash.create!(
        TaskDependency,
        %{from_slice_id: from.id, to_slice_id: to.id, kind: kind},
        domain: Factory
      )
    end)
  end
end
