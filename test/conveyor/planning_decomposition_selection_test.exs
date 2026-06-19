defmodule Conveyor.PlanningDecompositionSelectionTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.DecompositionSelection

  test "selects only strict hard-invariant dominance and never auto-blends candidates" do
    result =
      DecompositionSelection.select([
        candidate("a",
          coverage: 1.0,
          constraints_satisfied?: true,
          independence: 0.9,
          unapproved_scope?: false
        ),
        candidate("b",
          coverage: 0.8,
          constraints_satisfied?: true,
          independence: 0.6,
          unapproved_scope?: false
        )
      ])

    assert result.status == :selected
    assert result.selected_candidate_key == "a"
    assert result.selection_actor == :deterministic
    assert result.auto_blended? == false

    human =
      DecompositionSelection.select([
        candidate("a",
          coverage: 1.0,
          constraints_satisfied?: true,
          independence: 0.9,
          unapproved_scope?: false
        ),
        candidate("b",
          coverage: 1.0,
          constraints_satisfied?: true,
          independence: 0.9,
          unapproved_scope?: false
        )
      ])

    assert human.status == :human_decision_required
    assert human.selected_candidate_key == nil
    assert human.auto_blended? == false
  end

  test "unapproved scope prevents deterministic selection" do
    result =
      DecompositionSelection.select([
        candidate("a",
          coverage: 1.0,
          constraints_satisfied?: true,
          independence: 1.0,
          unapproved_scope?: true
        ),
        candidate("b",
          coverage: 0.8,
          constraints_satisfied?: true,
          independence: 0.8,
          unapproved_scope?: false
        )
      ])

    assert result.status == :human_decision_required
    assert result.selected_candidate_key == nil
  end

  defp candidate(key, attrs) do
    attrs
    |> Map.new()
    |> Map.merge(%{
      candidate_key: key,
      oracle_feasible?: true,
      atomicity_score: 1.0,
      edge_count: 1,
      interface_complexity: 1,
      approval_load: 1
    })
  end
end
