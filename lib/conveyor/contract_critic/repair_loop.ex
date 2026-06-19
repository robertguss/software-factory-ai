defmodule Conveyor.ContractCritic.RepairLoop do
  @moduledoc """
  Bounded automatic repair policy for Contract Critic findings.
  """

  @default_max_rounds 2
  @amendment_classes ~w(plan constraint interface acceptance)

  @spec next_action(map()) :: :repair | :park
  def next_action(input) when is_map(input) do
    completed_rounds = value(input, :completed_rounds) || 0
    max_rounds = value(input, :max_rounds) || @default_max_rounds

    if completed_rounds < max_rounds, do: :repair, else: :park
  end

  @spec evaluate(map()) :: map()
  def evaluate(input) when is_map(input) do
    artifact_digests = value(input, :artifact_digests) || []
    finding_counts = value(input, :finding_counts) || []
    evidence_refs = value(input, :evidence_refs) || []

    cond do
      oscillating?(artifact_digests) ->
        %{status: :parked, reason: :oscillation, evidence_refs: evidence_refs}

      non_progress?(finding_counts) ->
        %{status: :parked, reason: :non_progress, evidence_refs: evidence_refs}

      true ->
        %{status: :repairable, reason: :progressing, evidence_refs: evidence_refs}
    end
  end

  @spec route_change(map()) :: :repair_allowed | {:amendment_required, map()} | {:error, map()}
  def route_change(input) when is_map(input) do
    change_class = value(input, :change_class)
    materiality = value(input, :materiality)

    cond do
      value(input, :weakens_policy_or_acceptance) == true and blank?(value(input, :authority_ref)) ->
        {:error,
         %{
           rule_key: "repair.policy_or_acceptance_weakening",
           severity: :blocking,
           subject_key: change_class,
           message: "Repair cannot weaken policy or acceptance without normal authority"
         }}

      materiality in ["material", "breaking"] and change_class in @amendment_classes ->
        {:amendment_required, %{change_class: change_class, materiality: materiality}}

      true ->
        :repair_allowed
    end
  end

  defp oscillating?(values), do: Enum.count(values) != Enum.count(Enum.uniq(values))

  defp non_progress?([first | rest]), do: Enum.all?(rest, &(&1 >= first))
  defp non_progress?(_values), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
