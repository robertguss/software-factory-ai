defmodule Conveyor.Recovery.FeedbackLadder do
  @moduledoc """
  rt6k.4: declared per-attempt rework-feedback profiles. Instead of resending the same shape of
  prompt on every retry, the feedback escalates as attempts accumulate.

  This governs WHAT the retry prompt *contains* per rung (feedback content), and is orthogonal to
  two other levers: the budget/effort ladder (`Conveyor.AttemptBudget`, which tunes agent effort)
  and model escalation (out of scope here). The ladder is data — a table of per-rung directives —
  not scattered conditionals, so cassettes replay and the design-laws tests can assert its shape.

  Rungs are keyed off the retry attempt number:

    * attempt 2 (first retry) — baseline: findings + failing-test excerpt + prior-diff summary (the
      feedback the sibling beads already assemble). No extra directive.
    * attempt 3+ — escalated: the baseline plus an explicit "you have failed repeatedly, reconsider
      the approach" directive so the agent does not simply repeat the prior strategy.
  """

  @baseline_rung "baseline_feedback"
  @escalated_rung "escalated_feedback"

  # Extra instruction lines the retry prompt carries at a given rung, on top of the always-present
  # baseline feedback. Declared data, so the ladder shape is inspectable and golden-testable.
  @directives %{
    @baseline_rung => [],
    @escalated_rung => [
      "You have now failed the gate on multiple attempts. Reconsider the approach from first " <>
        "principles and change strategy — do not repeat the previous attempts."
    ]
  }

  @type t :: %{name: String.t(), directives: [String.t()]}

  @doc """
  The feedback rung for a retry at `next_attempt_no`. Attempt 2 (the first retry) is the baseline;
  attempt 3 and beyond escalate. `nil` (a non-laddered caller) maps to the baseline so it still
  receives the sibling-bead default feedback.
  """
  @spec rung(pos_integer() | nil) :: t()
  def rung(next_attempt_no) when is_integer(next_attempt_no) and next_attempt_no >= 3 do
    build(@escalated_rung)
  end

  def rung(_next_attempt_no), do: build(@baseline_rung)

  defp build(name), do: %{name: name, directives: Map.fetch!(@directives, name)}
end
