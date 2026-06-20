defmodule Conveyor.Planning.PlanRunner do
  @moduledoc """
  Loads a normalized plan contract and runs it through the width-1 SerialDriver.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, Plan, Project, Slice}
  alias Conveyor.PlanContract
  alias Conveyor.Planning.SerialDriver

  defmodule Result do
    @moduledoc "Plan-level serial run result."

    @enforce_keys [
      :adapter,
      :plan_path,
      :project,
      :plan,
      :epic,
      :slices_by_stable_key,
      :serial_result,
      :work_graph
    ]
    defstruct [
      :adapter,
      :plan_path,
      :project,
      :plan,
      :epic,
      :slices_by_stable_key,
      :serial_result,
      :work_graph
    ]
  end

  @spec run!(Path.t(), keyword()) :: Result.t()
  def run!(plan_path, opts \\ []) do
    {:ok, contract_result} = PlanContract.load(plan_path)
    contract = contract_result.contract

    workspace_path =
      Keyword.get(opts, :workspace_path) || Path.dirname(contract_result.source_path)

    adapter = Keyword.get(opts, :agent_adapter, Conveyor.AgentRunner.Codex)
    blob_root = Keyword.get(opts, :blob_root) || default_blob_root()

    project = create_project!(contract, workspace_path)
    plan = create_plan!(project, contract_result)
    epic = create_epic!(plan, contract)
    slices_by_stable_key = create_slices!(epic, contract)

    selected_slice_ids =
      Keyword.get_lazy(opts, :selected_slice_ids, fn -> slice_keys(contract) end)

    work_graph = work_graph(contract)

    serial_result =
      serial_driver().(
        %{
          work_graph: work_graph,
          selected_slice_ids: selected_slice_ids
        },
        [
          slices_by_stable_key: slices_by_stable_key,
          run_spec_opts: [
            plan_path: contract_result.source_path,
            workspace_path: workspace_path,
            blob_root: blob_root,
            agent_adapter: adapter
          ],
          actor: Keyword.get(opts, :actor, "conveyor.run")
        ]
        |> maybe_put(
          :patch_refs_by_slice,
          patch_refs_by_slice(contract_result, selected_slice_ids, opts)
        )
      )

    %Result{
      adapter: adapter,
      plan_path: contract_result.source_path,
      project: project,
      plan: plan,
      epic: epic,
      slices_by_stable_key: slices_by_stable_key,
      serial_result: serial_result,
      work_graph: work_graph
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
    Project
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.local_path == workspace_path))
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
        description: "Serial Conveyor run for #{plan.source_document}"
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

  defp work_graph(contract) do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" =>
        Enum.map(Map.fetch!(contract, "slices"), fn slice ->
          %{
            "stable_key" => Map.fetch!(slice, "key"),
            "title" => Map.fetch!(slice, "title"),
            "requirement_refs" => Map.get(slice, "requirement_refs", []),
            "likely_files" => Map.get(slice, "likely_files", []),
            "conflict_domains" => Map.get(slice, "conflict_domains", [])
          }
        end),
      "work_dependencies" => work_dependencies(contract)
    }
  end

  defp slice_keys(contract) do
    contract
    |> Map.fetch!("slices")
    |> Enum.map(&Map.fetch!(&1, "key"))
  end

  defp patch_refs_by_slice(contract_result, slice_keys, opts) do
    Keyword.get_lazy(opts, :patch_refs_by_slice, fn ->
      discover_reference_patches(contract_result.source_path, slice_keys)
    end)
  end

  defp discover_reference_patches(source_path, slice_keys) do
    canary_dir =
      source_path
      |> Path.dirname()
      |> Path.join(".conveyor/canary")

    patch_refs =
      Map.new(slice_keys, fn slice_key ->
        {slice_key, reference_patch_for(canary_dir, slice_key)}
      end)

    if Enum.all?(patch_refs, fn {_slice_key, patch_ref} -> is_binary(patch_ref) end) do
      patch_refs
    end
  end

  defp reference_patch_for(canary_dir, slice_key) do
    slice_number =
      slice_key
      |> String.replace_prefix("SLICE-", "")
      |> String.downcase()

    case Path.wildcard(Path.join(canary_dir, "reference_slice_#{slice_number}_*.patch")) do
      [patch_ref] -> patch_ref
      _missing_or_ambiguous -> nil
    end
  end

  defp work_dependencies(%{"work_dependencies" => dependencies}) when is_list(dependencies) do
    dependencies
  end

  defp work_dependencies(%{"slices" => slices}) do
    slices
    |> Enum.map(&Map.fetch!(&1, "key"))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] ->
      %{"from" => from, "to" => to, "kind" => "execution_hard"}
    end)
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp default_blob_root do
    Path.join(System.tmp_dir!(), "conveyor-blobs")
  end

  defp serial_driver do
    Process.get(:conveyor_run_serial_driver, &SerialDriver.run!/2)
  end
end
