defmodule Conveyor.Qualification.Gate do
  @moduledoc """
  Pure P15-B8 qualification gate evaluator.

  The gate checks whether an evidence package is eligible to become a scoped
  grant candidate. It does not issue authority by itself.
  """

  @required_hard_blockers ~w(
    registry
    canonicalization
    attestations
    derivation
    policy
    scope
    deterministic_conformance
    safety_trace_assertions
    canaries
    meta_canaries
    poison_pill
    fencing
    role_view
    hidden_oracle
    test_integrity
  )

  @required_replay_modes ~w(strict full hybrid)
  @passing_live_statuses ~w(quality_floor_met miss_observed)

  @spec required_hard_blockers() :: [String.t()]
  def required_hard_blockers, do: @required_hard_blockers

  @spec required_replay_modes() :: [String.t()]
  def required_replay_modes, do: @required_replay_modes

  @spec evaluate(map()) :: map()
  def evaluate(package) when is_map(package) do
    deterministic_checks = value(package, :deterministic_checks, [])
    replay_checks = value(package, :replay_checks, [])
    live_sample_run = value(package, :live_sample_run, %{})

    findings =
      []
      |> Enum.concat(hard_blocker_findings(deterministic_checks))
      |> Enum.concat(replay_findings(replay_checks))
      |> Enum.concat(live_policy_findings(live_sample_run))

    %{
      gate: :qualification_gate,
      project_id: value(package, :project_id),
      requested_scope: value(package, :requested_scope, %{}),
      status: if(findings == [], do: :passed, else: :blocked),
      authority_effect: if(findings == [], do: :qualification_grant_candidate, else: :none),
      findings: findings,
      finding_keys: findings |> Enum.map(& &1.rule_key) |> Enum.uniq(),
      live_sample_policy: %{
        worst_required_stratum_result: value(live_sample_run, :worst_required_stratum_result),
        stratum_results: value(live_sample_run, :stratum_results, [])
      }
    }
  end

  defp hard_blocker_findings(checks) do
    by_key = Map.new(checks, fn check -> {to_string(value(check, :key)), check} end)

    @required_hard_blockers
    |> Enum.reject(fn key -> passed?(Map.get(by_key, key)) end)
    |> Enum.map(fn key ->
      finding(
        "qualification_gate_hard_blocker_failed",
        key,
        reason(Map.get(by_key, key), "required hard blocker did not pass")
      )
    end)
  end

  defp replay_findings(checks) do
    by_mode = Map.new(checks, fn check -> {to_string(value(check, :mode)), check} end)

    @required_replay_modes
    |> Enum.reject(fn mode -> passed?(Map.get(by_mode, mode)) end)
    |> Enum.map(fn mode ->
      finding(
        "qualification_gate_replay_failed",
        mode,
        reason(Map.get(by_mode, mode), "required replay mode did not pass")
      )
    end)
  end

  defp live_policy_findings(live_sample_run) do
    worst = value(live_sample_run, :worst_required_stratum_result)

    if worst in @passing_live_statuses do
      []
    else
      [
        finding(
          "qualification_gate_live_policy_failed",
          "live_sample_policy",
          "live sample policy result #{inspect(worst)} is not grant-eligible"
        )
      ]
    end
  end

  defp passed?(nil), do: false
  defp passed?(check), do: value(check, :status) in [:passed, "passed", true]

  defp reason(nil, default), do: default
  defp reason(check, default), do: value(check, :reason, default)

  defp finding(rule_key, subject_key, message) do
    %{
      rule_key: rule_key,
      severity: :blocking,
      subject_key: subject_key,
      message: message
    }
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
