defmodule Conveyor.FailureDiagnosis do
  @moduledoc """
  Deterministic-first immutable failure diagnosis.

  Agent hypotheses are recorded as competing hypotheses only after structured
  evidence has been evaluated by stable rules.
  """

  @schema_version "conveyor.failure_diagnosis@1"
  @diagnostic_version "diagnosis-rules@1"
  @rule_bundle_digest "sha256:#{String.duplicate("d", 64)}"

  @spec diagnose(map()) :: map()
  def diagnose(context) when is_map(context) do
    context
    |> classify()
    |> build_diagnosis(context)
  end

  defp classify(context) do
    cond do
      emergency_stop_active?(context) ->
        deterministic(
          "emergency_stopped",
          ["emergency_stop_active"],
          ["emergency_stop:active"],
          "deterministic_rule:emergency_stop_active",
          [value(value(context, :emergency_stop), :evidence_ref)]
        )

      exhausted_budget = first_exhausted_budget(context) ->
        deterministic(
          "budget_exhausted",
          [value(exhausted_budget, :status) |> to_string()],
          ["budget:exhausted"],
          "deterministic_rule:budget_exhausted",
          [value(exhausted_budget, :evidence_ref)]
        )

      policy_denial = first_policy_denial(context) ->
        %{
          primary_classification: "policy_violation",
          contributing_factors: [value(policy_denial, :reason) || "policy_denied"],
          observations: ["policy_decision:deny"],
          confidence: 0.95,
          confidence_basis: "deterministic_rule:policy_decision_denied",
          abstained: false,
          evidence_refs: evidence_refs([policy_denial])
        }

      stale_replay?(context) ->
        deterministic(
          "cassette_stale",
          ["replay_stale"],
          ["replay:stale"],
          "deterministic_rule:replay_stale",
          [value(value(context, :replay), :evidence_ref)]
        )

      true ->
        %{
          primary_classification: "unknown",
          contributing_factors: [],
          observations: ["insufficient_structured_evidence"],
          confidence: 0.0,
          confidence_basis: "deterministic_rules_abstained",
          abstained: true,
          evidence_refs: []
        }
    end
  end

  defp deterministic(classification, factors, observations, confidence_basis, evidence_refs) do
    %{
      primary_classification: classification,
      contributing_factors: factors,
      observations: observations,
      confidence: 0.95,
      confidence_basis: confidence_basis,
      abstained: false,
      evidence_refs: Enum.reject(evidence_refs, &is_nil/1)
    }
  end

  defp emergency_stop_active?(context) do
    context
    |> value(:emergency_stop, %{})
    |> value(:active)
  end

  defp first_exhausted_budget(context) do
    context
    |> value(:budgets, [])
    |> Enum.find(&(to_string(value(&1, :status)) == "exhausted"))
  end

  defp build_diagnosis(classification, context) do
    diagnosis = %{
      "schema_version" => @schema_version,
      "subject" => value(context, :subject),
      "primary_classification" => classification.primary_classification,
      "contributing_factors" => classification.contributing_factors,
      "observations" => classification.observations,
      "competing_hypotheses" => competing_hypotheses(context),
      "confidence" => classification.confidence,
      "confidence_basis" => classification.confidence_basis,
      "abstained" => classification.abstained,
      "evidence_refs" => classification.evidence_refs,
      "rule_bundle_digest" => @rule_bundle_digest,
      "diagnostic_version" => @diagnostic_version
    }

    Map.put(diagnosis, "diagnosis_digest", digest(diagnosis))
  end

  defp first_policy_denial(context) do
    context
    |> value(:policy_decisions, [])
    |> Enum.find(&(to_string(value(&1, :result)) == "deny"))
  end

  defp stale_replay?(context) do
    context
    |> value(:replay, %{})
    |> value(:status)
    |> to_string()
    |> Kernel.==("stale")
  end

  defp competing_hypotheses(context) do
    context
    |> value(:agent_hypotheses, [])
    |> Enum.map(&to_string/1)
  end

  defp evidence_refs(records) do
    records
    |> Enum.map(&value(&1, :evidence_ref))
    |> Enum.reject(&is_nil/1)
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp digest(value) do
    digest_input =
      value
      |> normalize_for_digest()
      |> :erlang.term_to_binary()

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, digest_input), case: :lower)
  end

  defp normalize_for_digest(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), normalize_for_digest(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize_for_digest(values) when is_list(values),
    do: Enum.map(values, &normalize_for_digest/1)

  defp normalize_for_digest(value), do: value
end
