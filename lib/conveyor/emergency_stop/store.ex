defmodule Conveyor.EmergencyStop.Store do
  @moduledoc """
  a3hf.2.1.4: durable, ledger-backed emergency-stop activation. `Conveyor.EmergencyStop` is pure
  (in-memory transitions); this persists a trip as a `conveyor.emergency_stop_state@1` ledger event
  so the halt survives a restart and can be read back by the driver (safe-point check) and by the
  cockpit/digest projections.

  A scope (`:project` for now) is engaged until a later `cleared` transition supersedes it.
  `trip!/3` is idempotent on scope + reason, so re-detecting the same breach does not spam the ledger.
  """

  alias Conveyor.EmergencyStop
  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Ledger

  @engaged "emergency_stop.engaged"
  @cleared "emergency_stop.cleared"

  @doc "Engage an emergency stop for `scope`/`scope_id` and record it durably. Returns the state."
  @spec trip!(atom(), String.t(), keyword()) :: map()
  def trip!(scope, scope_id, opts) do
    state = EmergencyStop.engage(scope, scope_id, opts)

    Ledger.write!(%{
      project_id: Keyword.fetch!(opts, :project_id),
      run_attempt_id: Keyword.get(opts, :run_attempt_id),
      slice_id: Keyword.get(opts, :slice_id),
      type: @engaged,
      idempotency_key: "emergency_stop_engaged:#{scope}:#{scope_id}:#{state.reason}",
      payload: payload(state, scope_id)
    })

    state
  end

  @doc "Clear an engaged stop (requires a HumanDecision) and record the cleared transition durably."
  @spec clear!(map(), keyword()) :: map()
  def clear!(engaged_state, opts) do
    cleared = EmergencyStop.clear(engaged_state, opts)

    Ledger.write!(%{
      project_id: Keyword.fetch!(opts, :project_id),
      type: @cleared,
      idempotency_key:
        "emergency_stop_cleared:#{cleared.scope}:#{cleared.scope_id}:#{cleared.human_decision_id}",
      payload: payload(cleared, cleared.scope_id)
    })

    cleared
  end

  @doc "Whether `scope`/`scope_id` is currently engaged (latest transition is a trip, not a clear)."
  @spec engaged?(atom(), String.t()) :: boolean()
  def engaged?(scope, scope_id) do
    latest_transition(scope, scope_id) == @engaged
  end

  defp latest_transition(scope, scope_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&stop_event_for?(&1, scope, scope_id))
    |> Enum.sort_by(&{DateTime.to_unix(&1.occurred_at, :microsecond), rank(&1.type)})
    |> List.last()
    |> case do
      nil -> nil
      event -> event.type
    end
  end

  defp stop_event_for?(event, scope, scope_id) do
    event.type in [@engaged, @cleared] and
      event.payload["scope"] == to_string(scope) and
      to_string(event.payload["scope_id"]) == to_string(scope_id)
  end

  # On an identical timestamp a clear supersedes an engage — clearing always follows engaging.
  defp rank(@engaged), do: 0
  defp rank(@cleared), do: 1

  defp payload(state, scope_id) do
    state
    |> EmergencyStop.to_record()
    |> Map.put("scope_id", to_string(scope_id))
  end
end
