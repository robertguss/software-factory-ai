defmodule Conveyor.Cost.Estimator do
  @moduledoc """
  Cost estimator (a3hf.2.2.2): estimate a plan's token/$ cost from historical
  `conveyor.agent_usage@1` records grouped by slice archetype. Honest about
  uncertainty — returns a low/expected/high **range** (observed min / mean / max
  per archetype, summed over the plan's slices), never a false-precision point.

  Empty or non-matching history returns `{:no_basis, reason}` rather than a fake
  number. Plan slices whose archetype has no history are reported as uncovered.
  """

  @type usage :: %{optional(String.t()) => term()}
  @type band :: %{low: number(), expected: float(), high: number()}

  @spec estimate([String.t()], [usage()]) ::
          {:ok, %{tokens: band(), cost_usd: band(), coverage: map()}} | {:no_basis, String.t()}
  def estimate(_plan_archetypes, []),
    do: {:no_basis, "no historical agent_usage records to estimate from"}

  def estimate(plan_archetypes, history) when is_list(plan_archetypes) and is_list(history) do
    stats = stats_by_archetype(history)
    {covered, uncovered} = Enum.split_with(plan_archetypes, &Map.has_key?(stats, &1))

    if covered == [] do
      {:no_basis, "no historical basis for any plan slice archetype"}
    else
      {:ok,
       %{
         tokens: band(covered, stats, :tokens),
         cost_usd: band(covered, stats, :cost),
         coverage: %{
           covered: length(covered),
           uncovered: length(uncovered),
           sample_size: length(history)
         }
       }}
    end
  end

  defp band(archetypes, stats, dim) do
    entries = Enum.map(archetypes, &stats[&1][dim])

    %{
      low: entries |> Enum.map(& &1.min) |> Enum.sum(),
      expected: entries |> Enum.map(& &1.mean) |> Enum.sum(),
      high: entries |> Enum.map(& &1.max) |> Enum.sum()
    }
  end

  defp stats_by_archetype(history) do
    history
    |> Enum.group_by(&Map.get(&1, "archetype"))
    |> Map.new(fn {archetype, records} ->
      {archetype,
       %{tokens: dim_stats(records, "tokens"), cost: dim_stats(records, "cost_usd_estimated")}}
    end)
  end

  defp dim_stats(records, key) do
    values = Enum.map(records, &num(&1, key))
    %{min: Enum.min(values), max: Enum.max(values), mean: Enum.sum(values) / length(values)}
  end

  defp num(map, key) do
    case Map.get(map, key) do
      nil -> 0
      value -> value
    end
  end
end
