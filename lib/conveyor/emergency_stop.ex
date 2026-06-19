defmodule Conveyor.EmergencyStop do
  @moduledoc """
  Pure emergency-stop state transitions.
  """

  # ADR-11 requires an engaged stop to block new station starts, provider calls, tool calls,
  # claim publication, and external effects (not just runs/effects/reservations).
  @blocked_actions MapSet.new([
                     :run_attempt,
                     :planning_run,
                     :provider_call,
                     :tool_call,
                     :claim_publish,
                     :effect,
                     :budget_reservation
                   ])

  @spec engage(atom(), String.t(), keyword()) :: map()
  def engage(scope, scope_id, opts) do
    %{
      scope: scope,
      scope_id: scope_id,
      status: :engaged,
      actor: Keyword.fetch!(opts, :actor),
      reason: Keyword.fetch!(opts, :reason),
      trace_id: Keyword.fetch!(opts, :trace_id),
      engaged_at: Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
    }
  end

  @spec blocks?(map(), atom()) :: boolean()
  def blocks?(%{status: :engaged}, action), do: MapSet.member?(@blocked_actions, action)
  def blocks?(_state, _action), do: false

  @spec clear(map(), keyword()) :: map()
  def clear(%{status: :engaged} = state, opts) do
    human_decision_id =
      Keyword.get(opts, :human_decision_id) ||
        raise ArgumentError, "HumanDecision is required to clear an emergency stop"

    state
    |> Map.put(:status, :clear)
    |> Map.put(:cleared_by, Keyword.fetch!(opts, :actor))
    |> Map.put(:human_decision_id, human_decision_id)
    |> Map.put(
      :cleared_at,
      Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
    )
  end

  @doc """
  Projects the in-memory stop state onto a `conveyor.emergency_stop_state@1` record.

  The in-memory map keeps atoms (`status: :engaged`, `scope: :project`) for `blocks?/2` and
  `clear/2` pattern-matching; this is the schema-conformant wire/persistence shape: string
  enums, `project_id` for project scope, and a single `actor` (the most recent operator).
  """
  @spec to_record(map()) :: map()
  def to_record(state) when is_map(state) do
    %{
      "schema_version" => "conveyor.emergency_stop_state@1",
      "scope" => to_string(state.scope),
      "status" => to_string(state.status),
      "reason" => state.reason,
      "actor" => Map.get(state, :cleared_by) || state.actor,
      "trace_id" => state.trace_id
    }
    |> put_present("project_id", project_id(state))
    |> put_present("human_decision_id", Map.get(state, :human_decision_id))
    |> put_present("engaged_at", iso8601(Map.get(state, :engaged_at)))
    |> put_present("cleared_at", iso8601(Map.get(state, :cleared_at)))
  end

  defp project_id(%{scope: :project, scope_id: scope_id}), do: scope_id
  defp project_id(_state), do: nil

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(value) when is_binary(value), do: value
end
