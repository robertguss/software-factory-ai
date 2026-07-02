defmodule Conveyor.Digest.SummaryTest do
  @moduledoc "a3hf.1.1.1: DigestSummary read-model over the run ledger + cost."
  use ExUnit.Case, async: true

  alias Conveyor.Digest.Summary
  alias Conveyor.RunReadModel

  # Build a real (pure) run story from a seeded run.slice_outcome fold — no DB.
  defp story(run_id, statuses_by_slice) do
    order = statuses_by_slice |> Map.keys() |> Enum.sort()

    outcomes =
      statuses_by_slice
      |> Enum.with_index(1)
      |> Map.new(fn {{slice_id, status}, seq} ->
        {slice_id,
         %{
           "run_id" => run_id,
           "slice_id" => slice_id,
           "sequence" => seq,
           "status" => status,
           "blocked_by" => [],
           "findings" => []
         }}
      end)

    RunReadModel.project(run_id, order, outcomes, status: :complete)
  end

  defp usage(run, slice, tokens, cost) do
    %{"run_id" => run, "slice_id" => slice, "tokens" => tokens, "cost_usd_estimated" => cost}
  end

  test "night rollup tallies terminal dispositions across all runs" do
    stories = [
      story("R1", %{"S1" => "passed", "S2" => "parked", "S3" => "passed"}),
      story("R2", %{"S4" => "failed", "S5" => "skipped"})
    ]

    digest = Summary.build(stories)

    assert digest.totals.runs == 2
    assert digest.totals.slice_count == 5

    assert digest.totals.dispositions == %{
             merged: 2,
             parked: 1,
             skipped: 1,
             failed: 1,
             in_flight: 0
           }
  end

  test "per-run digest carries its own dispositions and needs-judgment count" do
    stories = [story("R1", %{"S1" => "passed", "S2" => "parked", "S3" => "questions_required"})]
    [run] = Summary.build(stories).runs

    assert run.run_id == "R1"
    assert run.dispositions.merged == 1
    assert run.dispositions.parked == 2
    assert run.needs_judgment == 2
  end

  test "cost section aggregates usage and remaining budget" do
    stories = [story("R1", %{"S1" => "passed"})]
    usage = [usage("R1", "S1", 300, 0.30), usage("R1", "S1", 200, 0.20)]
    budget = %{"token_limit" => 1_000, "cost_limit" => 1.00}

    digest = Summary.build(stories, usage, budget)

    assert digest.cost.totals.tokens == 500
    assert digest.cost.remaining.tokens == 500
    refute digest.cost.remaining.over_budget?
  end

  test "night rollup needs-judgment totals across runs" do
    stories = [
      story("R1", %{"S1" => "parked"}),
      story("R2", %{"S2" => "passed", "S3" => "parked"})
    ]

    assert Summary.build(stories).totals.needs_judgment == 2
  end

  test "an empty night yields zeroed totals and no cost overrun" do
    digest = Summary.build([])
    assert digest.totals.runs == 0
    assert digest.totals.dispositions.merged == 0
    assert digest.cost.totals.tokens == 0
  end
end
