defmodule Conveyor.TestArchitect.IntegrityGate do
  @moduledoc """
  Integrates Test-Integrity Sentinel results with per-obligation satisfaction.

  Hard Sentinel failures and unsatisfied obligation requirements block the gate.
  Signals that are advisory until calibrated, such as universal mutation without
  a reference and dynamic coverage, are reported separately and never hard-block.
  """

  alias Conveyor.Verification
  alias Conveyor.Verification.IntegritySentinel

  @passing_satisfaction_results ~w(satisfied waived)

  @spec evaluate!(map(), map(), [map()], keyword()) :: map()
  def evaluate!(integrity_spec, observations, obligation_inputs, opts)
      when is_map(integrity_spec) and is_map(observations) and is_list(obligation_inputs) and
             is_list(opts) do
    evaluated_at = Keyword.fetch!(opts, :evaluated_at)
    policy_decision_id = Keyword.fetch!(opts, :policy_decision_id)

    integrity_run =
      IntegritySentinel.run(integrity_spec, observations, evaluated_at: evaluated_at)

    obligation_satisfactions =
      Enum.map(obligation_inputs, fn input ->
        Verification.evaluate_requirement(
          value(input, :requirement),
          value(input, :evidence) || [],
          policy_decision_id: policy_decision_id,
          evaluated_at: evaluated_at,
          quarantines: value(input, :quarantines) || [],
          waiver: value(input, :waiver)
        )
      end)

    hard_findings = integrity_run["findings"] ++ satisfaction_findings(obligation_satisfactions)
    advisory_findings = advisory_findings(Keyword.get(opts, :advisory_checks, %{}))

    %{
      status: if(hard_findings == [], do: :passed, else: :blocked),
      integrity_run: integrity_run,
      obligation_satisfactions: obligation_satisfactions,
      hard_findings: hard_findings,
      advisory_findings: advisory_findings
    }
  end

  defp satisfaction_findings(satisfactions) do
    satisfactions
    |> Enum.reject(&(Map.fetch!(&1, "result") in @passing_satisfaction_results))
    |> Enum.map(fn satisfaction ->
      %{
        "rule_key" => "obligation_satisfaction.unsatisfied",
        "severity" => "blocking",
        "anchor" => Map.fetch!(satisfaction, "verification_obligation_id"),
        "result" => Map.fetch!(satisfaction, "result")
      }
    end)
  end

  defp advisory_findings(checks) when is_map(checks) do
    checks
    |> Enum.map(fn {key, status} ->
      %{
        "rule_key" => "test_integrity.advisory.#{key}",
        "severity" => "advisory",
        "status" => to_string(status)
      }
    end)
    |> Enum.sort_by(& &1["rule_key"])
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
