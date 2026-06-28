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
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice

  @type entry :: %{
          run_attempt_id: Ecto.UUID.t(),
          slice_id: Ecto.UUID.t(),
          slice_title: String.t() | nil,
          attempt_no: integer(),
          band: String.t() | nil,
          score: number() | nil,
          trust_score: map() | nil
        }

  @doc """
  Abstained run attempts (a passed gate the TrustScore was not confident about),
  each with its persisted trust verdict and slice, sorted least-trusted first so
  the most urgent review is on top.
  """
  @spec abstained() :: [entry()]
  def abstained do
    trust_by_attempt = trust_by_attempt()
    slices = slices_by_id()

    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.outcome == :abstained))
    |> Enum.map(&entry(&1, trust_by_attempt, slices))
    |> Enum.sort_by(&{score_key(&1.score), &1.run_attempt_id})
  end

  defp entry(attempt, trust_by_attempt, slices) do
    trust = Map.get(trust_by_attempt, attempt.id)
    slice = Map.get(slices, attempt.slice_id)

    %{
      run_attempt_id: attempt.id,
      slice_id: attempt.slice_id,
      slice_title: slice && slice.title,
      attempt_no: attempt.attempt_no,
      band: trust && trust["band"],
      score: trust && trust["score"],
      trust_score: trust
    }
  end

  defp trust_by_attempt do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(& &1.trust_score)
    # An attempt can carry multiple GateResults. `Map.new` keeps the LAST tuple
    # per `run_attempt_id`, so over `Ash.read!`'s unordered result the surviving
    # trust verdict was arbitrary. Sort by `id` first to make the winner stable
    # and reproducible: the highest-id verdict deterministically wins. (GateResult
    # has no timestamp column, so `id` — not recency — is the stable key.)
    |> Enum.sort_by(& &1.id)
    |> Map.new(&{&1.run_attempt_id, &1.trust_score})
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
