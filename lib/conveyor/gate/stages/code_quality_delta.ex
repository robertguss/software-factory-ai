defmodule Conveyor.Gate.Stages.CodeQualityDelta do
  @moduledoc """
  Gate stage 10: evaluates code-quality delta thresholds.

  Code-quality signals are advisory unless project policy selects the adapter as
  gate-blocking and the adapter declares a deterministic contract.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.CodeQualityAdapter.Result
  alias Conveyor.Gate.StageResult

  @result_schema Result.schema_version()

  @impl true
  def run(context, _opts \\ []) do
    run = value(context, :code_quality_run)
    result = value(context, :code_quality_result) || %{}
    contract = adapter_contract(context, result)
    adapter = value(run, :adapter) || value(result, :adapter)
    policy = quality_policy(context)
    selected? = gate_blocking_selected?(adapter, policy, context)
    contract_ready? = gate_blocking_contract?(contract)
    threshold = threshold(policy, contract)
    findings = findings(run, result, contract, selected?, contract_ready?, threshold)

    %StageResult{
      key: "code_quality_delta",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(run, result),
      input_digests: %{
        "adapter" => adapter,
        "profile" => value(run, :profile) || value(result, :profile),
        "baseline_ref" => value(run, :baseline_ref),
        "result_ref" => value(run, :result_ref),
        "gate_blocking_selected" => selected?,
        "deterministic_contract" => contract_ready?,
        "new_high_risk_findings_threshold" => threshold
      },
      output_digest:
        digest(%{
          adapter: adapter,
          run_status: value(run, :status) || value(result, :status),
          new_high_risk_findings: new_high_risk_findings(run, result),
          selected?: selected?,
          contract_ready?: contract_ready?,
          threshold: threshold
        })
    }
  end

  defp findings(nil, _result, _contract, true, _contract_ready?, _threshold) do
    [
      finding(
        "missing_code_quality_run",
        "blocking",
        "Gate-blocking code-quality policy selected an adapter, but no run was provided."
      )
    ]
  end

  defp findings(nil, _result, _contract, false, _contract_ready?, _threshold) do
    [
      finding(
        "missing_code_quality_run",
        "warning",
        "No code-quality run was provided; treating quality as advisory context only."
      )
    ]
  end

  defp findings(run, result, contract, selected?, contract_ready?, threshold) do
    []
    |> maybe_add_contract_finding(selected?, contract_ready?, contract)
    |> maybe_add_run_status_finding(run, result, selected?)
    |> maybe_add_threshold_finding(run, result, selected? and contract_ready?, threshold)
  end

  defp maybe_add_contract_finding(findings, true, false, contract) do
    [
      finding(
        "quality_adapter_contract_not_gate_blocking",
        "blocking",
        "Selected code-quality adapter does not declare a deterministic gate-blocking contract.",
        %{"adapter_contract" => contract}
      )
      | findings
    ]
  end

  defp maybe_add_contract_finding(findings, _selected?, _contract_ready?, _contract), do: findings

  defp maybe_add_run_status_finding(findings, run, result, selected?) do
    status = normalize_status(value(run, :status) || value(result, :status))

    cond do
      status in ["succeeded", nil] ->
        findings

      selected? ->
        [
          finding(
            "code_quality_run_failed",
            "blocking",
            "Gate-blocking code-quality run did not succeed.",
            %{"run_status" => status}
          )
          | findings
        ]

      true ->
        [
          finding(
            "code_quality_run_failed",
            "warning",
            "Advisory code-quality run did not succeed.",
            %{"run_status" => status}
          )
          | findings
        ]
    end
  end

  defp maybe_add_threshold_finding(findings, run, result, gate_blocking?, threshold) do
    count = new_high_risk_findings(run, result)

    if count > threshold do
      severity = if gate_blocking?, do: "blocking", else: "warning"

      [
        finding(
          "new_high_risk_findings",
          severity,
          "Code-quality delta introduced new high-risk findings.",
          %{"new_high_risk_findings" => count, "threshold" => threshold}
        )
        | findings
      ]
    else
      findings
    end
  end

  defp adapter_contract(context, result) do
    value(context, :code_quality_adapter_contract) ||
      value(context, :quality_adapter_contract) ||
      value(value(result, :metadata), :adapter_contract) ||
      %{}
  end

  defp quality_policy(context) do
    value(context, :code_quality_policy) ||
      value(context, :quality_gate_policy) ||
      value(context, :review_policy) ||
      %{}
  end

  defp gate_blocking_selected?(nil, policy, context) do
    value(context, :code_quality_gate_blocking) == true or value(policy, :gate_blocking) == true
  end

  defp gate_blocking_selected?(adapter, policy, context) do
    value(context, :code_quality_gate_blocking) == true or
      value(policy, :gate_blocking) == true or
      adapter in gate_blocking_adapters(policy, context)
  end

  defp gate_blocking_adapters(policy, context) do
    context_adapters =
      value(context, :gate_blocking_quality_adapters) ||
        value(context, :quality_gate_blocking_adapters) ||
        value(context, :code_quality_gate_blocking_adapters)

    policy_adapters =
      value(policy, :gate_blocking_quality_adapters) ||
        value(policy, :quality_gate_blocking_adapters) ||
        value(policy, :code_quality_gate_blocking_adapters)

    (List.wrap(context_adapters) ++ List.wrap(policy_adapters))
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp gate_blocking_contract?(contract) when is_map(contract) do
    value(contract, :deterministic_output) == true and
      value(contract, :result_schema) == @result_schema and
      present?(value(contract, :fixture_suite)) and
      is_map(value(contract, :threshold_policy)) and
      threshold_contract_allows_blocking?(contract)
  end

  defp gate_blocking_contract?(_contract), do: false

  defp threshold_contract_allows_blocking?(contract) do
    value(contract, :gate_blocking_when_selected) == true or
      value(contract, :advisory_only) != true
  end

  defp threshold(policy, contract) do
    policy_threshold =
      value(policy, :new_high_risk_findings_threshold) ||
        value(value(policy, :threshold_policy), :new_high_risk_findings)

    contract_threshold = value(value(contract, :threshold_policy), :new_high_risk_findings)
    non_negative_integer(policy_threshold) || non_negative_integer(contract_threshold) || 0
  end

  defp new_high_risk_findings(run, result) do
    non_negative_integer(value(run, :new_high_risk_findings)) ||
      non_negative_integer(value(result, :new_high_risk_findings)) ||
      0
  end

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: nil

  defp finding(category, severity, message, extra \\ %{}) do
    %{
      "category" => category,
      "severity" => severity,
      "message" => message
    }
    |> Map.merge(extra)
  end

  defp status(findings) do
    if Enum.any?(findings, &(&1["severity"] == "blocking")), do: :failed, else: :passed
  end

  defp evidence_refs(run, result) do
    [
      value(run, :baseline_ref),
      value(run, :result_ref),
      value(result, :result_ref),
      value(result, :artifact_ref)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp digest(value) do
    "sha256:" <>
      (:sha256
       |> :crypto.hash(:erlang.term_to_binary(value))
       |> Base.encode16(case: :lower))
  end

  defp normalize_status(nil), do: nil
  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(status), do: to_string(status)

  defp present?(value), do: value not in [nil, ""]

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp value(_value, _key), do: nil
end
