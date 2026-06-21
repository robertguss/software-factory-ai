defmodule Conveyor.Planning.RaceConductor do
  @moduledoc """
  ADR-25 — bounded speculative parallelism *within a single slice*.

  For a hard or high-risk slice, run N candidate attempts concurrently (different
  model / effort / seed), gate each, and keep the one that passes — selected
  deterministically by `TrustScore` then cost. This is parallelism for
  *reliability*, not throughput: candidates contend for one slice in isolated
  sandboxes, and only one winner ever merges, so it introduces no fleet, no
  dispatcher, no merge queue. Cross-slice posture stays width-1 (Law 27).

  Opt-in by construction: nothing calls this unless asked, and the default is a
  single candidate (width-1 behaviour). Winner selection is a pure function of the
  candidate results + a fixed policy, so a replay reproduces the same winner.
  """

  @type candidate_result :: %{
          required(:id) => term(),
          required(:passed?) => boolean(),
          optional(:score) => number(),
          optional(:cost) => number()
        }

  @doc """
  Select the winning candidate: among those that passed, the highest `TrustScore`,
  breaking ties by lowest `cost`. Returns `{:ok, winner}` or `:no_winner`. Pure.
  """
  @spec select_winner([candidate_result()]) :: {:ok, candidate_result()} | :no_winner
  def select_winner(results) when is_list(results) do
    results
    |> Enum.filter(& &1.passed?)
    |> Enum.sort_by(&{-score(&1), cost(&1)})
    |> case do
      [winner | _rest] -> {:ok, winner}
      [] -> :no_winner
    end
  end

  @doc """
  Race candidates: run each through `run_fn` (returning a `candidate_result`)
  concurrently, then select the winner. Returns `{:winner, winner, all_results}`
  or `{:no_winner, all_results}`. `run_fn` is the seam — the conductor never
  touches sandboxes/gates directly, so this is fully testable with a fake.
  """
  @spec race([term()], (term() -> candidate_result()), keyword()) ::
          {:winner, candidate_result(), [candidate_result()]} | {:no_winner, [candidate_result()]}
  def race(candidates, run_fn, opts \\ [])
      when is_list(candidates) and is_function(run_fn, 1) and is_list(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, max(length(candidates), 1))
    timeout = Keyword.get(opts, :timeout, 300_000)

    results =
      candidates
      |> Task.async_stream(run_fn, max_concurrency: max_concurrency, timeout: timeout)
      |> Enum.map(fn {:ok, result} -> result end)

    case select_winner(results) do
      {:ok, winner} -> {:winner, winner, results}
      :no_winner -> {:no_winner, results}
    end
  end

  defp score(result), do: Map.get(result, :score, 0.0)
  defp cost(result), do: Map.get(result, :cost, 0)
end
