defmodule Conveyor.Planning.Preview do
  @moduledoc """
  Assembles a plan dry-run preview (a3hf.2.2.3): the computed work graph, each slice's
  contract summary, the non-blocking plan-lint warnings, and a cost estimate — everything a
  human needs to sanity-check a plan BEFORE approving it, so no tokens are spent until the
  approve-to-run gate (`mix conveyor.plan.approve`) is crossed.

  Read-only: this never approves or runs anything.
  """

  alias Conveyor.Cost.Estimator
  alias Conveyor.Factory
  alias Conveyor.Factory.Plan
  alias Conveyor.Planning.PlanWarnings
  alias Conveyor.Planning.WorkGraphBuilder

  @spec assemble(binary(), keyword()) :: map()
  def assemble(plan_id, opts \\ []) when is_binary(plan_id) do
    plan = Ash.get!(Plan, plan_id, domain: Factory)
    contract = plan.normalized_contract || %{}
    graph = WorkGraphBuilder.build(plan)
    slices = Map.get(graph, "slices", [])

    %{
      plan_id: plan.id,
      status: to_string(plan.status),
      slices: Enum.map(slices, &slice_summary/1),
      dependencies: Map.get(graph, "work_dependencies", []),
      warnings: PlanWarnings.warn(contract, warnings_graph(graph)),
      estimate: estimate(slices, usage_history(opts)),
      approved?: plan.status == :approved
    }
  end

  defp slice_summary(slice) do
    %{
      "stable_key" => slice["stable_key"],
      "title" => slice["title"],
      "requirement_refs" => slice["requirement_refs"] || [],
      "likely_files" => slice["likely_files"] || []
    }
  end

  # WorkGraphBuilder emits `work_dependencies` (from/to/kind); SliceDependency (used by
  # PlanWarnings) reads `dependencies` and requires a `rationale`. Adapt in place rather than
  # widening the shared analyzer — the edges are declared, so the rationale is exactly that.
  defp warnings_graph(graph) do
    dependencies =
      graph
      |> Map.get("work_dependencies", [])
      |> Enum.map(&Map.put(&1, "rationale", "declared dependency"))

    %{"slices" => Map.get(graph, "slices", []), "dependencies" => dependencies}
  end

  # No per-slice archetype is recorded yet, so every slice maps to the dominant "implement"
  # archetype; with no historical usage the estimator honestly returns {:no_basis, _}.
  defp estimate(slices, usage) do
    archetypes = Enum.map(slices, fn _ -> "implement" end)

    case Estimator.estimate(archetypes, usage) do
      {:ok, est} -> %{basis: "historical", tokens: est.tokens, cost_usd: est.cost_usd}
      {:no_basis, reason} -> %{basis: "none", reason: reason}
    end
  end

  # Historical agent_usage@1 records are not yet aggregated into a preview-time source
  # (tracked with the cost cockpit); until then callers may inject usage, else it is empty
  # and the estimate is honestly no-basis.
  defp usage_history(opts), do: Keyword.get(opts, :usage, [])
end
