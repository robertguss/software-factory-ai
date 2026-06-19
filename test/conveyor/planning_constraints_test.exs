defmodule Conveyor.PlanningConstraintsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.Constraints

  test "hard constraint violations block regardless of soft score" do
    constraint_set =
      Constraints.new("plan-revision-1", [
        %{
          key: "api-compatible",
          strength: :hard,
          violation_policy: :block,
          validation_kind: :static_diff
        },
        %{
          key: "prefer-small-diff",
          strength: :soft,
          violation_policy: :warn,
          validation_kind: :scored
        }
      ])

    report =
      Constraints.evaluate(constraint_set, %{
        "api-compatible" => :violated,
        "prefer-small-diff" => :satisfied
      })

    assert report.verdict == :blocked
    assert report.status_by_key["api-compatible"] == :violated
    assert report.hard_violations == ["api-compatible"]
  end

  test "soft violations warn without blocking" do
    constraint_set =
      Constraints.new("plan-revision-1", [
        %{key: "prefer-small-diff", strength: :soft, violation_policy: :warn}
      ])

    report = Constraints.evaluate(constraint_set, %{"prefer-small-diff" => :violated})

    assert report.verdict == :warn
    assert report.soft_violations == ["prefer-small-diff"]
    assert report.hard_violations == []
  end
end
