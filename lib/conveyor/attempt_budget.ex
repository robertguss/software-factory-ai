defmodule Conveyor.AttemptBudget do
  @moduledoc """
  Typed retry-attempt budget and escalation ladder.
  """

  @default_ladder [
    %{"rung" => "same_effort", "agent_profile_patch" => %{}},
    %{
      "rung" => "codex_reasoning_effort:minimal",
      "agent_profile_patch" => %{"codex_reasoning_effort" => "minimal"}
    },
    %{
      "rung" => "codex_reasoning_effort:low",
      "agent_profile_patch" => %{"codex_reasoning_effort" => "low"}
    },
    %{
      "rung" => "codex_reasoning_effort:medium",
      "agent_profile_patch" => %{"codex_reasoning_effort" => "medium"}
    },
    %{
      "rung" => "codex_reasoning_effort:high",
      "agent_profile_patch" => %{"codex_reasoning_effort" => "high"}
    },
    %{"rung" => "failing_test_pinned_brief", "agent_profile_patch" => %{}}
  ]

  @enforce_keys [:max_attempts, :ladder]
  defstruct [:max_attempts, :ladder]

  @spec new(keyword()) :: %__MODULE__{}
  def new(opts) do
    ladder = Keyword.get(opts, :attempt_ladder, @default_ladder)

    %__MODULE__{
      max_attempts: Keyword.get(opts, :max_attempts, length(ladder) + 1),
      ladder: ladder
    }
  end

  @spec retry_allowed?(%__MODULE__{}, non_neg_integer()) :: boolean()
  def retry_allowed?(%__MODULE__{} = budget, completed_attempt_count) do
    completed_attempt_count < budget.max_attempts and
      not is_nil(rung_for_retry(budget, completed_attempt_count + 1))
  end

  @spec rung_for_retry(%__MODULE__{}, pos_integer()) :: map() | nil
  def rung_for_retry(%__MODULE__{} = budget, next_attempt_no) when next_attempt_no >= 2 do
    Enum.at(budget.ladder, next_attempt_no - 2)
  end
end
