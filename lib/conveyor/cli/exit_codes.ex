defmodule Conveyor.CLI.ExitCodes do
  @moduledoc "Stable Conveyor CLI exit codes."

  @codes %{
    success: 0,
    deterministic_gate_failed: 1,
    plan_or_readiness_blocked: 2,
    policy_or_secret_safety_violation: 3,
    infrastructure_or_doctor_failure: 4,
    adapter_failure: 5,
    canary_or_eval_false_negative: 6,
    malformed_artifact_or_schema_failure: 7,
    # dr1m.6.1/KTD-3: a run that PARKED ≥1 slice for human review (trust abstained,
    # reaped, rework-exhausted, or skipped behind a parked predecessor) and hit no
    # hard gate failure — "needs a human", distinct from deterministic_gate_failed.
    parked_for_review: 8,
    # uevc.2: bad CLI invocation or a disposition that cannot be applied (e.g. approve blocked by a
    # patch conflict) — an operator-actionable error distinct from the gate/infra failure classes.
    usage: 9
  }

  @spec all() :: %{atom() => non_neg_integer()}
  def all, do: @codes

  @spec fetch!(atom()) :: non_neg_integer()
  def fetch!(key), do: Map.fetch!(@codes, key)
end
