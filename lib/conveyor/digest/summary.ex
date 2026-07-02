defmodule Conveyor.Digest.Summary do
  @moduledoc """
  DigestSummary read-model (a3hf.1.1.1): folds `Conveyor.RunReadModel` stories (the
  event-sourced run ledger + GateResult, already reconstructed) and a cost aggregation
  into a per-run + per-night digest — each run's terminal dispositions, needs-judgment
  count, and aggregate cost vs budget. Pure read path; no writes.

  Slice `outcome` strings (written by the SerialDriver to `run.slice_outcome`) normalize
  to dispositions: `passed → :merged`, `parked`/`questions_required → :parked`,
  `skipped`/`baseline_absent → :skipped`, `nil → :in_flight`, anything else → `:failed`.
  Needs-judgment counts the parked slices (parked = a human is required).
  """

  alias Conveyor.Cost.ReadModel
  alias Conveyor.RunReadModel

  @dispositions [:merged, :parked, :skipped, :failed, :in_flight]

  @spec build([RunReadModel.story()], [map()], map() | nil) :: map()
  def build(stories, usage_records \\ [], budget_envelope \\ nil)
      when is_list(stories) and is_list(usage_records) do
    runs = Enum.map(stories, &run_digest/1)

    %{
      runs: runs,
      totals: night_totals(runs),
      cost: ReadModel.aggregate(usage_records, budget_envelope)
    }
  end

  defp run_digest(story) do
    dispositions = tally(story.slices)

    %{
      run_id: story.run_id,
      status: story.status,
      slice_count: length(story.slices),
      dispositions: dispositions,
      needs_judgment: dispositions.parked
    }
  end

  defp tally(slices) do
    zeroed = Map.new(@dispositions, &{&1, 0})

    Enum.reduce(slices, zeroed, fn slice, acc ->
      key = disposition(slice.outcome)
      Map.update!(acc, key, &(&1 + 1))
    end)
  end

  defp disposition("passed"), do: :merged
  defp disposition(status) when status in ["parked", "questions_required"], do: :parked
  defp disposition(status) when status in ["skipped", "baseline_absent"], do: :skipped
  defp disposition(nil), do: :in_flight
  defp disposition(_other), do: :failed

  defp night_totals(runs) do
    %{
      runs: length(runs),
      slice_count: Enum.sum(Enum.map(runs, & &1.slice_count)),
      needs_judgment: Enum.sum(Enum.map(runs, & &1.needs_judgment)),
      dispositions: sum_dispositions(runs)
    }
  end

  defp sum_dispositions(runs) do
    Map.new(@dispositions, fn key ->
      {key, Enum.sum(Enum.map(runs, &(&1.dispositions[key] || 0)))}
    end)
  end
end
