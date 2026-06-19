defmodule Conveyor.EmergencyStop do
  @moduledoc """
  Pure emergency-stop state transitions.
  """

  @blocked_actions MapSet.new([:run_attempt, :planning_run, :effect, :budget_reservation])

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
end
