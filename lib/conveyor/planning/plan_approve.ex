defmodule Conveyor.Planning.PlanApprove do
  @moduledoc """
  Bulk lock + approve every drafted slice of a DB-native plan behind a plan-lint
  gate (aaun.1). `preview/1` is the read-only pre-flight (lint + per-slice
  summary); `approve_all!/1` re-checks lint, then locks and approves the still
  drafted slices in dependency (position) order. Both refuse a lint-failing plan
  so bulk-approve never becomes bulk-rubber-stamp.
  """

  require Ash.Query

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Slice
  alias Conveyor.Planning.PlanLint
  alias Conveyor.TaskGraph

  @type lint :: map()

  @spec preview(binary()) :: {:ok, %{lint: lint(), slices: [map()]}} | {:blocked, lint()}
  def preview(plan_id) when is_binary(plan_id) do
    plan = Ash.get!(Plan, plan_id, domain: Factory)

    case lint_gate(plan) do
      {:ok, lint} -> {:ok, %{lint: lint, slices: Enum.map(slices(plan), &summary/1)}}
      {:blocked, lint} -> {:blocked, lint}
    end
  end

  @spec approve_all!(binary()) ::
          {:ok, %{approved: [binary()], already_approved: [binary()]}} | {:blocked, lint()}
  def approve_all!(plan_id) when is_binary(plan_id) do
    plan = Ash.get!(Plan, plan_id, domain: Factory)

    case lint_gate(plan) do
      {:ok, _lint} ->
        {drafted, done} = Enum.split_with(slices(plan), &(&1.state == :drafted))

        {:ok,
         %{
           approved: Enum.map(drafted, &lock_and_approve!/1),
           already_approved: Enum.map(done, & &1.stable_key)
         }}

      {:blocked, lint} ->
        {:blocked, lint}
    end
  end

  # Lint gates the AUTHORED plan (status :draft). Once a slice is locked the plan's
  # rows are compiled into `normalized_contract` and the status advances — at that point
  # the gate already passed at first lock, and the persisted compiled contract is not the
  # lint input, so re-linting it is both wrong and redundant.
  defp lint_gate(%Plan{status: :draft} = plan) do
    lint = PlanLint.lint(plan.normalized_contract || %{})
    if lint.status == :passed, do: {:ok, lint}, else: {:blocked, lint}
  end

  defp lint_gate(%Plan{}), do: {:ok, %{status: :passed, findings: [], already_gated: true}}

  defp lock_and_approve!(%Slice{} = slice) do
    TaskGraph.lock_task(slice.id)
    TaskGraph.approve_task(slice.id)
    slice.stable_key
  end

  defp slices(%Plan{} = plan) do
    epic_ids = plan.id |> epics() |> Enum.map(& &1.id)

    Slice
    |> Ash.Query.filter(epic_id in ^epic_ids)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(domain: Factory)
  end

  defp epics(plan_id) do
    Epic |> Ash.Query.filter(plan_id == ^plan_id) |> Ash.read!(domain: Factory)
  end

  defp summary(%Slice{} = slice) do
    %{
      "stable_key" => slice.stable_key,
      "title" => slice.title,
      "likely_files" => length(slice.likely_files || []),
      "acceptance_criteria" => length(slice.acceptance_criteria || []),
      "state" => to_string(slice.state)
    }
  end
end
