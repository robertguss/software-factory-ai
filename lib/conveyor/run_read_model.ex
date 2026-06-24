defmodule Conveyor.RunReadModel do
  @moduledoc """
  U1: a read-only "run story" folded from a run's committed ledger stream + DB enrichment.

  Takes a `run_id` and returns a plain map: the run's terminal status, the ordered slices
  (each carrying its committed outcome, the failing gate stage + trust verdict, rework count,
  and token spend), and the stop point (the slice the run was on when it halted, or `nil`
  when every slice has an outcome).

  This is the data source for the U2 CLI — it returns structured data, never formatted text.

  Read-only projection: it reads the ledger (the source of truth) and the Factory resources
  and **never** writes or repairs the ledger. It reuses the existing folds rather than
  re-deriving them:

    * `Conveyor.Planning.RunReconstruction.load_outcomes/1` for the `run.slice_outcome` fold,
      and `reconstruct/3` for the deterministic order's stop point (`in_flight_slice`).
    * `Conveyor.Planning.RunReconciler.route/...`'s terminal classification, mirrored here as
      `classify_status/1`.
    * `Mix.Tasks.Conveyor.Show`'s `latest_run_attempt/1` + `trust_verdict/1` per-slice
      enrichment pattern, and the gate-stage access from the same task / `run_viewer_live`.

  The projection splits into a PURE part (`project/3`, building the skeleton from an injected
  `order` + `outcomes` map + terminal status — no DB) and the DB enrichment (`summarize/1` +
  `enrich_slice/2`), so the fold is unit-testable without Postgres.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Planning.RunReconstruction

  # Mirrors RunReconciler's @lifecycle_types: the run-lifecycle events that carry terminal state.
  @lifecycle_types ~w(run.started run.finished run.reaped run.parked run.resumed)

  @type status :: :complete | :reaped | :parked | :interrupted | :unknown

  @type gate :: %{
          failed_stage: String.t() | nil,
          failed_status: String.t() | nil,
          verdict: %{optional(String.t()) => term()} | nil
        }

  @type spend :: %{tokens: integer() | nil, cost_estimate: Decimal.t() | nil} | :unknown

  @type slice_story :: %{
          slice_id: String.t(),
          sequence: integer() | nil,
          outcome: String.t() | nil,
          run_attempt_outcome: String.t() | nil,
          gate: gate(),
          rework_attempts: non_neg_integer(),
          spend: spend()
        }

  @type story :: %{
          run_id: String.t(),
          status: status(),
          stop_point: String.t() | nil,
          slice_count: non_neg_integer(),
          slices: [slice_story()]
        }

  @doc """
  Build the full run story for `run_id` from the ledger plus per-slice DB enrichment.

  Reads the lifecycle events (for order + terminal status) and the `run.slice_outcome`
  fold from the ledger, builds the pure skeleton, then enriches each slice with its latest
  `RunAttempt` (gate stage/verdict, rework count, token spend). An unknown/eventless
  `run_id` returns `status: :unknown`, `stop_point: nil`, and empty `slices` — no crash.
  """
  @spec summarize(String.t()) :: story()
  def summarize(run_id) when is_binary(run_id) do
    lifecycle = lifecycle_events(run_id)
    status = classify_status(lifecycle)
    order = order_from(lifecycle)
    outcomes = RunReconstruction.load_outcomes(run_id)

    run_id
    |> project(order, outcomes, status: status)
    |> enrich()
  end

  @doc """
  Pure projection: the run-story skeleton from an injected slice `order`, a
  `slice_id => run.slice_outcome payload` map, and the terminal `status`.

  No DB access — the gate/rework/spend fields are placeholders the DB enrichment
  (`enrich/1`) fills in. Mirrors `planning_run_reconstruction_test`'s injected-`outcomes`
  style so the fold is unit-testable without Postgres. The stop point is
  `RunReconstruction.reconstruct/3`'s `in_flight_slice` (the first ordered slice with no
  committed outcome; `nil` when all have outcomes).
  """
  @spec project(String.t(), [String.t()], %{optional(String.t()) => map()}, keyword()) :: story()
  def project(run_id, order, outcomes, opts \\ [])
      when is_binary(run_id) and is_list(order) and is_map(outcomes) do
    status = Keyword.get(opts, :status, :unknown)
    state = RunReconstruction.reconstruct(run_id, order, outcomes: outcomes)

    slices =
      Enum.map(order, fn slice_id ->
        payload = Map.get(outcomes, slice_id, %{})

        %{
          slice_id: slice_id,
          sequence: payload["sequence"],
          outcome: payload["status"],
          run_attempt_outcome: payload["run_attempt_outcome"],
          gate: %{failed_stage: nil, failed_status: nil, verdict: nil},
          rework_attempts: 0,
          spend: :unknown
        }
      end)

    %{
      run_id: run_id,
      status: status,
      stop_point: state.in_flight_slice,
      slice_count: length(order),
      slices: slices
    }
  end

  @doc """
  Classify a run's terminal status from its lifecycle events (mirrors `RunReconciler.route`).

    * a `run.finished` event   -> `:complete`
    * a `run.reaped` event     -> `:reaped` (the run-budget deadline halted it)
    * a `run.parked` event     -> `:parked`
    * a `run.started` with no terminal -> `:interrupted` (a crash)
    * no `run.started` at all   -> `:unknown`

  A per-slice `reaped` inside a `run.slice_outcome` payload is NOT a run reap — only the
  lifecycle `run.reaped` event is — so only lifecycle events are passed here.
  """
  @spec classify_status([LedgerEvent.t()]) :: status()
  def classify_status(lifecycle_events) when is_list(lifecycle_events) do
    types = MapSet.new(lifecycle_events, & &1.type)

    cond do
      not MapSet.member?(types, "run.started") -> :unknown
      MapSet.member?(types, "run.finished") -> :complete
      MapSet.member?(types, "run.reaped") -> :reaped
      MapSet.member?(types, "run.parked") -> :parked
      true -> :interrupted
    end
  end

  # --- DB enrichment ---------------------------------------------------------

  # Fill each pure slice's gate / rework / spend from the DB. Reads each resource once and
  # joins in memory (the repo-wide `Ash.read! |> Enum.filter` pattern this codebase uses),
  # so enrichment is O(resources) reads, not O(slices).
  @spec enrich(story()) :: story()
  defp enrich(%{slices: []} = story), do: story

  defp enrich(%{slices: slices} = story) do
    attempts = read(RunAttempt)
    gate_results = read(GateResult)
    sessions = read(AgentSession)

    attempts_by_slice = Enum.group_by(attempts, & &1.slice_id)

    %{
      story
      | slices: Enum.map(slices, &enrich_slice(&1, attempts_by_slice, gate_results, sessions))
    }
  end

  @spec enrich_slice(
          slice_story(),
          %{optional(String.t()) => [RunAttempt.t()]},
          [GateResult.t()],
          [
            AgentSession.t()
          ]
        ) :: slice_story()
  defp enrich_slice(slice, attempts_by_slice, gate_results, sessions) do
    slice_attempts = Map.get(attempts_by_slice, slice.slice_id, [])
    latest = latest_attempt(slice_attempts)

    %{
      slice
      | rework_attempts: length(slice_attempts),
        gate: gate_for(latest, gate_results),
        spend: spend_for(latest, sessions)
    }
  end

  # Latest attempt = highest attempt_no (mirrors conveyor.show's `sort_by(attempt_no, :desc)`).
  @spec latest_attempt([RunAttempt.t()]) :: RunAttempt.t() | nil
  defp latest_attempt([]), do: nil

  defp latest_attempt(attempts) do
    attempts |> Enum.sort_by(& &1.attempt_no, :desc) |> List.first()
  end

  @spec gate_for(RunAttempt.t() | nil, [GateResult.t()]) :: gate()
  defp gate_for(nil, _gate_results), do: %{failed_stage: nil, failed_status: nil, verdict: nil}

  defp gate_for(attempt, gate_results) do
    gate_result =
      gate_results
      |> Enum.filter(&(&1.run_attempt_id == attempt.id))
      |> List.last()

    {failed_stage, failed_status} = failing_stage(gate_result)

    %{
      failed_stage: failed_stage,
      failed_status: failed_status,
      verdict: verdict(gate_result)
    }
  end

  # GateResult.stages is a LIST of maps, each with a string "key" (stage name) and "status".
  # The failing stage is the first whose "status" is not "passed" (mirrors conveyor.show /
  # run_viewer_live's `&1["key"]` access). Persisted stages use STRING keys.
  @spec failing_stage(GateResult.t() | nil) :: {String.t() | nil, String.t() | nil}
  defp failing_stage(nil), do: {nil, nil}

  defp failing_stage(%{stages: stages}) when is_list(stages) do
    case Enum.find(stages, &(&1["status"] != "passed")) do
      nil -> {nil, nil}
      stage -> {stage["key"], stage["status"]}
    end
  end

  defp failing_stage(_gate_result), do: {nil, nil}

  # The calibrated trust verdict (band/score) from the gate's trust_score map (ADR-23),
  # mirroring conveyor.show's `Map.take(trust_score, ["band", "score"])`.
  @spec verdict(GateResult.t() | nil) :: %{optional(String.t()) => term()} | nil
  defp verdict(%{trust_score: trust_score}) when is_map(trust_score),
    do: Map.take(trust_score, ["band", "score"])

  defp verdict(_gate_result), do: nil

  # Token spend for the latest attempt's AgentSessions. AgentSession joins via run_attempt_id
  # (it has no slice_id). `tokens`/`cost_estimate` are nullable and currently have no writer,
  # so they are usually nil: if EVERY session's `tokens` is nil, report `:unknown` (never 0).
  @spec spend_for(RunAttempt.t() | nil, [AgentSession.t()]) :: spend()
  defp spend_for(nil, _sessions), do: :unknown

  defp spend_for(attempt, sessions) do
    attempt_sessions = Enum.filter(sessions, &(&1.run_attempt_id == attempt.id))
    tokens = attempt_sessions |> Enum.map(& &1.tokens) |> Enum.reject(&is_nil/1)

    if tokens == [] do
      :unknown
    else
      %{tokens: Enum.sum(tokens), cost_estimate: sum_cost(attempt_sessions)}
    end
  end

  @spec sum_cost([AgentSession.t()]) :: Decimal.t() | nil
  defp sum_cost(sessions) do
    sessions
    |> Enum.map(& &1.cost_estimate)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      costs -> Enum.reduce(costs, Decimal.new(0), &Decimal.add/2)
    end
  end

  # --- ledger reads ----------------------------------------------------------

  @spec lifecycle_events(String.t()) :: [LedgerEvent.t()]
  defp lifecycle_events(run_id) do
    LedgerEvent
    |> read()
    |> Enum.filter(&(&1.type in @lifecycle_types and &1.payload["run_id"] == run_id))
  end

  # Deterministic slice order from the run.started event's payload "slice_ids".
  @spec order_from([LedgerEvent.t()]) :: [String.t()]
  defp order_from(lifecycle_events) do
    case Enum.find(lifecycle_events, &(&1.type == "run.started")) do
      nil -> []
      started -> List.wrap(started.payload["slice_ids"])
    end
  end

  @spec read(module()) :: [struct()]
  defp read(resource), do: Ash.read!(resource, domain: Factory)
end
