defmodule Conveyor.AttemptBudgetTest do
  @moduledoc """
  Characterization tests for `Conveyor.AttemptBudget` — the rework loop's retry budget
  and escalation ladder (M2). Pure logic; no DB.
  """
  use ExUnit.Case, async: true

  alias Conveyor.AttemptBudget

  describe "new/1" do
    test "defaults to the built-in 6-rung ladder and max_attempts = rungs + 1" do
      budget = AttemptBudget.new([])

      assert length(budget.ladder) == 6
      assert budget.max_attempts == 7
      assert hd(budget.ladder)["rung"] == "same_effort"
    end

    test "accepts a custom ladder (max_attempts tracks its length)" do
      ladder = [%{"rung" => "only", "agent_profile_patch" => %{}}]
      budget = AttemptBudget.new(attempt_ladder: ladder)

      assert budget.ladder == ladder
      assert budget.max_attempts == 2
    end

    test "accepts an explicit max_attempts override" do
      assert AttemptBudget.new(max_attempts: 3).max_attempts == 3
    end
  end

  describe "rung_for_retry/2 — the escalation ladder" do
    setup do
      %{budget: AttemptBudget.new([])}
    end

    test "maps the 2nd attempt onward to successive rungs (escalating codex effort)", %{
      budget: budget
    } do
      assert AttemptBudget.rung_for_retry(budget, 2)["rung"] == "same_effort"
      assert AttemptBudget.rung_for_retry(budget, 3)["rung"] == "codex_reasoning_effort:minimal"
      assert AttemptBudget.rung_for_retry(budget, 4)["rung"] == "codex_reasoning_effort:low"
      assert AttemptBudget.rung_for_retry(budget, 5)["rung"] == "codex_reasoning_effort:medium"
      assert AttemptBudget.rung_for_retry(budget, 6)["rung"] == "codex_reasoning_effort:high"
      assert AttemptBudget.rung_for_retry(budget, 7)["rung"] == "failing_test_pinned_brief"
    end

    test "the effort rungs carry the matching agent_profile_patch", %{budget: budget} do
      assert AttemptBudget.rung_for_retry(budget, 3)["agent_profile_patch"] == %{
               "codex_reasoning_effort" => "minimal"
             }

      assert AttemptBudget.rung_for_retry(budget, 6)["agent_profile_patch"] == %{
               "codex_reasoning_effort" => "high"
             }
    end

    test "returns nil past the end of the ladder", %{budget: budget} do
      assert AttemptBudget.rung_for_retry(budget, 8) == nil
    end
  end

  describe "retry_allowed?/2" do
    setup do
      %{budget: AttemptBudget.new([])}
    end

    test "allows a retry while attempts remain and a rung exists", %{budget: budget} do
      assert AttemptBudget.retry_allowed?(budget, 1)
      assert AttemptBudget.retry_allowed?(budget, 6)
    end

    test "denies a retry once max_attempts is reached", %{budget: budget} do
      refute AttemptBudget.retry_allowed?(budget, 7)
      refute AttemptBudget.retry_allowed?(budget, 8)
    end

    test "a tighter max_attempts caps retries before the ladder runs out" do
      budget = AttemptBudget.new(max_attempts: 3)

      assert AttemptBudget.retry_allowed?(budget, 2)
      refute AttemptBudget.retry_allowed?(budget, 3)
    end

    # Characterization (not an endorsement): retry_allowed?/2 is only well-defined for
    # completed_attempt_count >= 1 — attempt 1 always runs unconditionally, so the loop
    # never asks "may I retry?" with zero completed attempts. With 0, rung_for_retry/2's
    # `next_attempt_no >= 2` guard has no matching clause.
    test "is undefined for zero completed attempts (guarded clause, never hit in the loop)", %{
      budget: budget
    } do
      assert_raise FunctionClauseError, fn -> AttemptBudget.retry_allowed?(budget, 0) end
    end
  end
end
