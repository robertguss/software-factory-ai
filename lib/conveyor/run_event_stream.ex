defmodule Conveyor.RunEventStream do
  @moduledoc """
  uevc.3: a read-only chronological projection of a run's ledger events — the source for
  `mix conveyor.watch`. Renders from ledger events only (no new state), so it works identically on a
  live run (poll + re-read) and a finished one (deterministic replay).

  A run's events span two link shapes: run-lifecycle + `run.slice_outcome` events carry
  `payload["run_id"]`, while attempt-level events (attempt transitions, gate verdicts, sentinel/scope
  parks) carry a `run_attempt_id`. Both are gathered: the run's attempts are bridged from the
  `run.started` event's `slice_ids` → slices → run_attempts (the same stable-key bridge the run read
  model uses), so an attempt event joins the stream even without a `run_id` in its payload.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice

  @type event :: %{
          id: String.t(),
          type: String.t(),
          occurred_at: DateTime.t(),
          slice_id: String.t() | nil,
          run_attempt_id: String.t() | nil,
          payload: map()
        }

  @doc "The run's ledger events, oldest-first. Ties on `occurred_at` break by id for determinism."
  @spec for_run(String.t()) :: [event()]
  def for_run(run_id) when is_binary(run_id) do
    events = read(LedgerEvent)
    attempt_ids = attempt_ids_for_run(run_id, events)

    events
    |> Enum.filter(&run_scoped?(&1, run_id, attempt_ids))
    |> Enum.sort_by(&{&1.occurred_at, &1.id}, __MODULE__.OccurredThenId)
    |> Enum.map(&to_event/1)
  end

  defmodule OccurredThenId do
    @moduledoc false
    def compare({at1, id1}, {at2, id2}) do
      case DateTime.compare(at1, at2) do
        :eq -> cmp(id1, id2)
        other -> other
      end
    end

    defp cmp(a, b) when a < b, do: :lt
    defp cmp(a, b) when a > b, do: :gt
    defp cmp(_a, _b), do: :eq
  end

  defp run_scoped?(event, run_id, attempt_ids) do
    event.payload["run_id"] == run_id or
      (event.run_attempt_id != nil and MapSet.member?(attempt_ids, event.run_attempt_id))
  end

  defp attempt_ids_for_run(run_id, events) do
    slice_keys = MapSet.new(started_slice_ids(events, run_id))

    slice_ids =
      Slice
      |> read()
      |> Enum.filter(&MapSet.member?(slice_keys, &1.stable_key))
      |> MapSet.new(& &1.id)

    RunAttempt
    |> read()
    |> Enum.filter(&MapSet.member?(slice_ids, &1.slice_id))
    |> MapSet.new(& &1.id)
  end

  defp started_slice_ids(events, run_id) do
    case Enum.find(events, &(&1.type == "run.started" and &1.payload["run_id"] == run_id)) do
      nil -> []
      started -> List.wrap(started.payload["slice_ids"])
    end
  end

  defp to_event(event) do
    %{
      id: event.id,
      type: event.type,
      occurred_at: event.occurred_at,
      slice_id: event.slice_id,
      run_attempt_id: event.run_attempt_id,
      payload: event.payload
    }
  end

  defp read(resource), do: Ash.read!(resource, domain: Factory)
end
