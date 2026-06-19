defmodule Conveyor.Planning.Constraints do
  @moduledoc """
  Pure ConstraintSet evaluator with hard-constraint precedence.
  """

  @spec new(String.t(), [map()]) :: map()
  def new(plan_revision_id, constraints) when is_list(constraints) do
    normalized = Enum.map(constraints, &normalize_constraint/1)

    %{
      plan_revision_id: plan_revision_id,
      hard_count: Enum.count(normalized, &(&1.strength == :hard)),
      soft_count: Enum.count(normalized, &(&1.strength == :soft)),
      constraints: normalized
    }
  end

  @spec evaluate(map(), map()) :: map()
  def evaluate(constraint_set, observed_statuses) when is_map(observed_statuses) do
    status_by_key =
      Map.new(constraint_set.constraints, fn constraint ->
        {constraint.key, Map.get(observed_statuses, constraint.key, :not_assessed)}
      end)

    hard_violations =
      violation_keys(constraint_set.constraints, status_by_key, :hard)

    soft_violations =
      violation_keys(constraint_set.constraints, status_by_key, :soft)

    %{
      status_by_key: status_by_key,
      hard_violations: hard_violations,
      soft_violations: soft_violations,
      verdict: verdict(hard_violations, soft_violations)
    }
  end

  defp normalize_constraint(constraint) do
    %{
      key: value(constraint, :key),
      strength: value(constraint, :strength),
      violation_policy: value(constraint, :violation_policy),
      validation_kind: value(constraint, :validation_kind)
    }
  end

  defp violation_keys(constraints, status_by_key, strength) do
    constraints
    |> Enum.filter(&(&1.strength == strength))
    |> Enum.filter(&(Map.fetch!(status_by_key, &1.key) in [:violated, :at_risk]))
    |> Enum.map(& &1.key)
  end

  defp verdict([_ | _], _soft), do: :blocked
  defp verdict([], [_ | _]), do: :warn
  defp verdict([], []), do: :passed

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
