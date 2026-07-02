defmodule Conveyor.Cost.ReadModel do
  @moduledoc """
  Cost read-model (a3hf.2.1.1): aggregates `conveyor.agent_usage@1` records into
  per-dimension totals (run / slice / agent / attempt) with running totals against
  a `conveyor.budget_envelope@1`.

  A usage record is an `agent_usage@1` map (tokens / cost_usd_estimated / latency_ms,
  adapter) tagged with the dimension keys of where it was captured — `run_id`,
  `slice_id`, `attempt_no`. Aggregation is pure and deterministic so the projection
  is stable and replayable; the cockpit (a3hf.2.1) consumes it.
  """

  @type usage :: %{optional(String.t()) => term()}
  @type totals :: %{
          tokens: non_neg_integer(),
          cost_usd: float(),
          latency_ms: non_neg_integer(),
          count: non_neg_integer()
        }

  @spec aggregate([usage()], usage() | nil) :: map()
  def aggregate(records, budget_envelope \\ nil) when is_list(records) do
    totals = totals(records)

    %{
      by_run: group_totals(records, "run_id"),
      by_slice: group_totals(records, "slice_id"),
      by_agent: group_totals(records, "adapter"),
      by_attempt: group_totals(records, "attempt_no"),
      totals: totals,
      remaining: remaining(totals, budget_envelope)
    }
  end

  defp group_totals(records, key) do
    records
    |> Enum.group_by(&Map.get(&1, key))
    |> Map.new(fn {dimension, group} -> {dimension, totals(group)} end)
  end

  defp totals(records) do
    Enum.reduce(records, %{tokens: 0, cost_usd: 0.0, latency_ms: 0, count: 0}, fn record, acc ->
      %{
        tokens: acc.tokens + num(record, "tokens"),
        cost_usd: acc.cost_usd + num(record, "cost_usd_estimated"),
        latency_ms: acc.latency_ms + num(record, "latency_ms"),
        count: acc.count + 1
      }
    end)
  end

  defp remaining(_totals, nil), do: nil

  defp remaining(totals, envelope) do
    token_remaining = num(envelope, "token_limit") - totals.tokens
    cost_remaining = num(envelope, "cost_limit") - totals.cost_usd

    %{
      tokens: token_remaining,
      cost_usd: cost_remaining,
      over_budget?: token_remaining < 0 or cost_remaining < 0
    }
  end

  defp num(map, key) do
    case Map.get(map, key) do
      nil -> 0
      value -> value
    end
  end
end
