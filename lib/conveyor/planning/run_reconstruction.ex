defmodule Conveyor.Planning.RunReconstruction do
  @moduledoc """
  U3: rebuild a run's loop state purely from its committed ledger stream.

  Folds the `run.slice_outcome` events for a `run_id` (written by the SerialDriver
  run ledger, U1/U2) into a `ResumeState` the resume entry path (U4) maps back into
  the reduce accumulator. Pure with respect to the workspace — it reads the ledger
  (the source of truth) and touches no git tree; exactly-once side-effect
  reconciliation against the live workspace is U5's job.

  "Passed" slices are the durable boundary and are never re-run. The resume point is
  the first slice in the run's deterministic `order` that has no committed outcome —
  the slice that was in flight when the run was interrupted.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent

  defmodule ResumeState do
    @moduledoc "Folded view of a run's committed progress, consumed by `SerialDriver.resume!/3`."

    @type t :: %__MODULE__{
            run_id: String.t(),
            outcomes_by_slice: %{optional(String.t()) => map()},
            passed_slice_ids: MapSet.t(),
            blocked: MapSet.t(),
            start_index: non_neg_integer(),
            in_flight_slice: String.t() | nil
          }

    @enforce_keys [:run_id, :outcomes_by_slice, :passed_slice_ids, :blocked, :start_index]
    defstruct [
      :run_id,
      :outcomes_by_slice,
      :passed_slice_ids,
      :blocked,
      :start_index,
      :in_flight_slice
    ]
  end

  @doc """
  Fold the committed stream for `run_id` against the run's deterministic slice `order`.

  `opts[:outcomes]` injects an already-loaded `slice_id => payload` map (used by tests
  and by callers that have the stream in hand); otherwise the `run.slice_outcome`
  events are read from the ledger.
  """
  @spec reconstruct(String.t(), [String.t()], keyword()) :: ResumeState.t()
  def reconstruct(run_id, order, opts \\ []) when is_binary(run_id) and is_list(order) do
    outcomes = Keyword.get_lazy(opts, :outcomes, fn -> load_outcomes(run_id) end)

    passed = slice_set(outcomes, &(&1["status"] == "passed"))
    blocked = slice_set(outcomes, &(&1["status"] != "passed"))

    start_index = Enum.find_index(order, &(not Map.has_key?(outcomes, &1))) || length(order)

    %ResumeState{
      run_id: run_id,
      outcomes_by_slice: outcomes,
      passed_slice_ids: passed,
      blocked: blocked,
      start_index: start_index,
      in_flight_slice: Enum.at(order, start_index)
    }
  end

  @doc "Load the committed `slice_id => outcome payload` map for a run from the ledger."
  @spec load_outcomes(String.t()) :: %{optional(String.t()) => map()}
  def load_outcomes(run_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.type == "run.slice_outcome" and &1.payload["run_id"] == run_id))
    |> Enum.sort_by(& &1.payload["sequence"])
    |> Map.new(&{&1.payload["slice_id"], &1.payload})
  end

  defp slice_set(outcomes, pred) do
    for {slice_id, payload} <- outcomes, pred.(payload), into: MapSet.new(), do: slice_id
  end
end
