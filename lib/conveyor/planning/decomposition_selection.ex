defmodule Conveyor.Planning.DecompositionSelection do
  @moduledoc """
  Deterministic candidate comparison and selection.

  A candidate is selected only when it strictly dominates on hard invariants
  without unapproved scope. Ties and ambiguous comparisons require a
  HumanDecision; candidates are never auto-blended.
  """

  defstruct [
    :status,
    :selected_candidate_key,
    :selection_actor,
    :selection_rationale,
    :comparison,
    :auto_blended?
  ]

  @spec select([map()]) :: %__MODULE__{}
  def select(candidates) when is_list(candidates) do
    comparison = Enum.map(candidates, &comparison_row/1)
    eligible = Enum.filter(comparison, &eligible?/1)

    selected =
      Enum.find(eligible, fn candidate ->
        others = Enum.reject(eligible, &(&1.candidate_key == candidate.candidate_key))
        others != [] and Enum.all?(others, &dominates?(candidate, &1))
      end)

    if selected do
      %__MODULE__{
        status: :selected,
        selected_candidate_key: selected.candidate_key,
        selection_actor: :deterministic,
        selection_rationale:
          "Candidate strictly dominates eligible alternatives on hard invariants.",
        comparison: comparison,
        auto_blended?: false
      }
    else
      %__MODULE__{
        status: :human_decision_required,
        selected_candidate_key: nil,
        selection_actor: :human,
        selection_rationale: "No candidate strictly dominates without unapproved scope.",
        comparison: comparison,
        auto_blended?: false
      }
    end
  end

  defp comparison_row(candidate) do
    %{
      candidate_key: value(candidate, :candidate_key),
      coverage: value(candidate, :coverage) || 0.0,
      constraints_satisfied?: value(candidate, :constraints_satisfied?) == true,
      independence: value(candidate, :independence) || 0.0,
      oracle_feasible?: value(candidate, :oracle_feasible?) == true,
      atomicity_score: value(candidate, :atomicity_score) || 0.0,
      edge_count: value(candidate, :edge_count) || 0,
      interface_complexity: value(candidate, :interface_complexity) || 0,
      approval_load: value(candidate, :approval_load) || 0,
      unapproved_scope?: value(candidate, :unapproved_scope?) == true
    }
  end

  defp eligible?(candidate) do
    candidate.constraints_satisfied? and candidate.oracle_feasible? and
      not candidate.unapproved_scope?
  end

  defp dominates?(left, right) do
    comparable = [
      left.coverage >= right.coverage,
      left.independence >= right.independence,
      left.atomicity_score >= right.atomicity_score,
      left.edge_count <= right.edge_count,
      left.interface_complexity <= right.interface_complexity,
      left.approval_load <= right.approval_load
    ]

    strictly_better = [
      left.coverage > right.coverage,
      left.independence > right.independence,
      left.atomicity_score > right.atomicity_score,
      left.edge_count < right.edge_count,
      left.interface_complexity < right.interface_complexity,
      left.approval_load < right.approval_load
    ]

    Enum.all?(comparable) and Enum.any?(strictly_better)
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
