defmodule Conveyor.PlanningDecomposerTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.Decomposer

  test "produces artifact-only primary and optional shadow candidates without canonical IDs" do
    plan = %{
      risk: :high,
      requirements: [%{key: "REQ-001", text: "Tasks must be completed."}]
    }

    result = Decomposer.propose(plan, shadow?: true)

    assert Enum.map(result.candidates, & &1.role) == [:primary, :shadow]
    assert Enum.all?(result.candidates, &(&1.artifact_only? == true))
    refute Enum.any?(result.candidates, &Map.has_key?(&1, :canonical_id))

    primary = hd(result.candidates)

    assert primary.epics != []
    assert primary.slices != []
    assert primary.work_deps == []
    assert primary.interfaces != []
    assert primary.risk != nil
    assert primary.preliminary_acceptance_criteria != []
    assert primary.why_this_slice != nil
    assert primary.assumptions != []
  end

  test "does not run a shadow candidate for low-risk plans" do
    result =
      Decomposer.propose(
        %{risk: :low, requirements: [%{key: "REQ-001", text: "Tasks must be completed."}]},
        shadow?: true
      )

    assert Enum.map(result.candidates, & &1.role) == [:primary]
  end
end
