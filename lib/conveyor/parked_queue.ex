defmodule Conveyor.ParkedQueue do
  @moduledoc """
  The operator's triage surface — the data foundation for the "needs-a-human"
  inbox (ADR-23 raw-leverage payoff).

  ADR-23 makes the gate abstain on passed-but-unconfident runs and persists the
  calibrated verdict on the `GateResult`. This module reads that back so the human
  reviews **only** what the machine honestly flagged, least-trusted first.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice

  @type entry :: %{
          run_attempt_id: Ecto.UUID.t(),
          slice_id: Ecto.UUID.t(),
          slice_title: String.t() | nil,
          attempt_no: integer(),
          band: String.t() | nil,
          score: number() | nil,
          park_reason: String.t() | nil,
          diff_stat: map() | nil,
          trust_score: map() | nil
        }

  @doc """
  Abstained run attempts (a passed gate the TrustScore was not confident about),
  each with its persisted trust verdict and slice, sorted least-trusted first so
  the most urgent review is on top.
  """
  @spec abstained() :: [entry()]
  def abstained do
    gate_results = gate_result_by_attempt()
    slices = slices_by_id()
    diff_stats = diff_stat_by_attempt()

    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.outcome == :abstained))
    |> Enum.map(&entry(&1, gate_results, slices, diff_stats))
    |> Enum.sort_by(&{score_key(&1.score), &1.run_attempt_id})
  end

  defp entry(attempt, gate_results, slices, diff_stats) do
    gate_result = Map.get(gate_results, attempt.id)
    trust = gate_result && gate_result.trust_score
    slice = Map.get(slices, attempt.slice_id)

    %{
      run_attempt_id: attempt.id,
      slice_id: attempt.slice_id,
      slice_title: slice && slice.title,
      attempt_no: attempt.attempt_no,
      band: trust && trust["band"],
      score: trust && trust["score"],
      park_reason: gate_result && gate_result.park_reason,
      diff_stat: Map.get(diff_stats, attempt.id),
      trust_score: trust
    }
  end

  # Latest PatchSet scope metrics per attempt, so triage shows how big the parked change is.
  defp diff_stat_by_attempt do
    PatchSet
    |> Ash.read!(domain: Factory)
    |> Enum.sort_by(&{DateTime.to_unix(&1.generated_at, :microsecond), &1.id})
    |> Map.new(fn patch_set ->
      {patch_set.run_attempt_id,
       %{
         "files_changed" => length(patch_set.changed_files),
         "lines_added" => patch_set.lines_added,
         "lines_deleted" => patch_set.lines_deleted
       }}
    end)
  end

  defp gate_result_by_attempt do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(& &1.trust_score)
    # An attempt can carry multiple GateResults. `Map.new` keeps the LAST tuple per
    # `run_attempt_id`, so sort ascending by created_at (uuid id as a same-microsecond
    # tiebreaker) and let the MOST RECENT verdict win — deterministic and recency-true.
    |> Enum.sort_by(&{DateTime.to_unix(&1.created_at, :microsecond), &1.id})
    |> Map.new(&{&1.run_attempt_id, &1})
  end

  defp slices_by_id do
    Slice
    |> Ash.read!(domain: Factory)
    |> Map.new(&{&1.id, &1})
  end

  # Sort missing scores last (treat as most-trusted/least-urgent).
  defp score_key(nil), do: {1, 0.0}
  defp score_key(score), do: {0, score}
end
