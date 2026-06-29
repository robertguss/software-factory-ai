defmodule Conveyor.Planning.PlanRunner do
  @moduledoc """
  Runs a persisted, DB-native plan through the width-1 `SerialDriver`.

  YAML is retired as the source of truth (U7): `conveyor run` takes a plan-id and reads the graph
  from the DB. Legacy YAML plans are brought in once via `Conveyor.Planning.PlanImporter`.
  """

  require Ash.Query

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, Plan, Project, Slice}
  alias Conveyor.Planning.SerialDriver
  alias Conveyor.Planning.WorkGraphBuilder

  defmodule UnapprovedError do
    @moduledoc "Raised when `conveyor run <plan-id>` is asked to execute an unapproved graph (R5)."
    defexception [:message, :unapproved]
  end

  defmodule Result do
    @moduledoc "Plan-level serial run result."

    @type t :: %__MODULE__{
            adapter: module() | binary(),
            plan_path: binary() | nil,
            project: struct(),
            plan: struct(),
            epic: struct(),
            slices_by_stable_key: %{optional(binary()) => struct()},
            serial_result: term(),
            work_graph: term()
          }

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

  @doc """
  Run a persisted, DB-native plan by id (R3, R5, R6).

  Resolves the plan's existing rows (no recreation), enforces the human approval gate (refuses if
  any selected task is still `:drafted`), builds the work graph via `WorkGraphBuilder`, and hands it
  to `SerialDriver` with the default `materialize_contract?: true` — because `lock` already produced
  a `:ready` contract, the assembler short-circuits to the locked artifacts with no
  re-materialization (KTD3/KTD8). Raises `UnapprovedError` *before* the driver is invoked.
  """
  @spec run_plan!(binary(), keyword()) :: Result.t()
  def run_plan!(plan_id, opts \\ []) when is_binary(plan_id) do
    plan = Ash.get!(Plan, plan_id, domain: Factory)
    project = Ash.get!(Project, plan.project_id, domain: Factory)
    epics = plan_epics(plan.id)
    slices = plan_slices(Enum.map(epics, & &1.id))

    enforce_approved!(slices)

    slices_by_stable_key = Map.new(slices, &{&1.stable_key, &1})
    selected_slice_ids = Enum.map(slices, & &1.stable_key)
    work_graph = WorkGraphBuilder.build(plan)
    adapter = Keyword.get(opts, :agent_adapter, Conveyor.AgentRunner.ClaudeCode)

    serial_result =
      serial_driver().(
        %{work_graph: work_graph, selected_slice_ids: selected_slice_ids},
        slices_by_stable_key: slices_by_stable_key,
        run_spec_opts: [
          workspace_path: Keyword.get(opts, :workspace_path),
          blob_root: Keyword.get(opts, :blob_root) || default_blob_root(),
          agent_adapter: adapter
        ],
        actor: Keyword.get(opts, :actor, "conveyor.run")
      )

    %Result{
      adapter: adapter,
      plan_path: "db:#{plan_id}",
      project: project,
      plan: plan,
      epic: List.first(epics),
      slices_by_stable_key: slices_by_stable_key,
      serial_result: serial_result,
      work_graph: work_graph
    }
  end

  defp plan_epics(plan_id) do
    Epic |> Ash.Query.filter(plan_id == ^plan_id) |> Ash.read!(domain: Factory)
  end

  defp plan_slices(epic_ids) do
    Slice
    |> Ash.Query.filter(epic_id in ^epic_ids)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(domain: Factory)
  end

  defp enforce_approved!(slices) do
    case Enum.filter(slices, &(&1.state == :drafted)) do
      [] ->
        :ok

      unapproved ->
        keys = Enum.map(unapproved, & &1.stable_key)

        raise UnapprovedError,
          message: "refusing to run: unapproved tasks #{Enum.join(keys, ", ")}",
          unapproved: keys
    end
  end

  defp default_blob_root do
    Path.join(System.tmp_dir!(), "conveyor-blobs")
  end

  defp serial_driver do
    Process.get(:conveyor_run_serial_driver, &SerialDriver.run!/2)
  end
end
