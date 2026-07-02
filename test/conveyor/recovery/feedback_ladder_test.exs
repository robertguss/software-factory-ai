defmodule Conveyor.Recovery.FeedbackLadderTest do
  @moduledoc """
  rt6k.4: the declared per-attempt feedback ladder. Data, not conditionals — attempt 2 (first retry)
  is the baseline; attempt 3+ escalates with an explicit "change your approach" directive. The
  induced-failure e2e that proves escalation end-to-end is rt6k.5.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Recovery.FeedbackLadder

  test "attempt 2 (first retry) is the baseline rung with no extra directives" do
    rung = FeedbackLadder.rung(2)

    assert rung.name == "baseline_feedback"
    assert rung.directives == []
  end

  test "a non-laddered caller (nil attempt) maps to the baseline rung" do
    assert FeedbackLadder.rung(nil).name == "baseline_feedback"
  end

  test "attempt 3+ escalates to a rung that instructs a change of approach" do
    for attempt_no <- [3, 4, 9] do
      rung = FeedbackLadder.rung(attempt_no)

      assert rung.name == "escalated_feedback"
      assert rung.directives != []
      assert Enum.any?(rung.directives, &(&1 =~ ~r/reconsider|change.*approach/i))
    end
  end

  test "the ladder is deterministic — same attempt yields the same rung" do
    assert FeedbackLadder.rung(3) == FeedbackLadder.rung(3)
  end
end
