defmodule Conveyor.PlanningPreliminaryVerificationTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PreliminaryVerification

  test "derives required open obligations from acceptance criteria and protected policies" do
    input = %{
      acceptance_criteria: [
        %{key: "AC-001", slice_key: "SLC-FILTER", obligation_kind: "property"},
        %{key: "AC-002", slice_key: "SLC-FILTER", obligation_kind: "interface"}
      ],
      protected_policies: [
        %{key: "POL-NO-SECRET", slice_key: "SLC-FILTER"}
      ]
    }

    first = PreliminaryVerification.derive(input)
    second = PreliminaryVerification.derive(input)

    assert first.status == :ok
    assert first.obligations == second.obligations
    assert Enum.map(first.obligations, & &1["acceptance_ref"]) == ["AC-001", "AC-002", "POL-NO-SECRET"]
    assert Enum.map(first.obligations, & &1["obligation_kind"]) == ["property", "interface", "policy"]
    assert Enum.all?(first.obligations, &(&1["slice_id"] == "SLC-FILTER"))
    assert Enum.all?(first.obligations, &(&1["required"] == true))
    assert Enum.all?(first.obligations, &(&1["status"] == "open"))
    assert Enum.all?(first.obligations, &String.starts_with?(&1["oracle_definition_ref"], "oracle:"))
    assert Enum.all?(first.obligations, &String.starts_with?(&1["evidence_requirement_ref"], "evidence_requirement:"))
    assert first.diagnostics == []
  end

  test "reports criteria without Slice ownership instead of fabricating obligations" do
    result =
      PreliminaryVerification.derive(%{
        acceptance_criteria: [%{key: "AC-ORPHAN", obligation_kind: "example"}],
        protected_policies: []
      })

    assert result.status == :blocked
    assert result.obligations == []

    assert result.diagnostics == [
             %{
               rule_key: "verification_obligation_missing_slice",
               severity: :blocking,
               subject_key: "AC-ORPHAN"
             }
           ]
  end
end
