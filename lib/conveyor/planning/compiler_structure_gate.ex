defmodule Conveyor.Planning.CompilerStructureGate do
  @moduledoc """
  Internal, non-authorizing compiler structure gate.
  """

  @authority_fields [
    {:creates_contract_lock?, "contract_lock"},
    {:creates_approval?, "approval"},
    {:creates_ready_slice?, "ready_slice"},
    {:implementer_launched?, "implementer"}
  ]

  @spec evaluate(map(), [map()]) :: map()
  def evaluate(package, findings) when is_map(package) and is_list(findings) do
    package = normalize(package)
    findings = Enum.map(findings, &normalize/1)

    gate_findings =
      findings
      |> Enum.filter(&blocking?/1)
      |> Enum.concat(package_findings(package))
      |> Enum.concat(authority_findings(package))

    %{
      gate_kind: :internal_non_authorizing,
      status: if(gate_findings == [], do: :passed, else: :blocked),
      exit_code: if(gate_findings == [], do: 0, else: 2),
      authority_effect: :none,
      creates_contract_lock?: false,
      creates_approval?: false,
      creates_ready_slice?: false,
      implementer_launched?: false,
      findings: gate_findings,
      finding_keys: Enum.map(gate_findings, &Map.fetch!(&1, :rule_key))
    }
  end

  defp package_findings(package) do
    status = get(package, :status)
    package_kind = get(package, :package_kind)

    cond do
      present?(status) and status != :complete ->
        [
          finding(
            "compiler_gate_incomplete_package",
            "package",
            "compiler structure gate requires a complete static decision package"
          )
        ]

      present?(package_kind) and package_kind != :static_decision_package ->
        [
          finding(
            "compiler_gate_wrong_package_kind",
            "package",
            "compiler structure gate only accepts static decision packages"
          )
        ]

      true ->
        []
    end
  end

  defp authority_findings(package) do
    field_effects =
      @authority_fields
      |> Enum.filter(fn {field, _effect} -> truthy?(get(package, field)) end)
      |> Enum.map(fn {_field, effect} -> effect end)

    authority_effect = get(package, :authority_effect)

    effects =
      if present?(authority_effect) and authority_effect != :none do
        [to_string(authority_effect) | field_effects]
      else
        field_effects
      end

    case Enum.uniq(effects) do
      [] ->
        []

      effects ->
        [
          finding(
            "compiler_gate_authority_created",
            Enum.join(effects, ","),
            "compiler structure gate is NON-authorizing and cannot create authority"
          )
        ]
    end
  end

  defp blocking?(finding), do: get(finding, :severity) == :blocking

  defp finding(rule_key, subject_key, message) do
    %{
      rule_key: rule_key,
      severity: :blocking,
      subject_key: subject_key,
      message: message
    }
  end

  defp normalize(%{} = map) do
    Map.new(map, fn {key, value} ->
      {normalize_key(key), normalize_value(value)}
    end)
  end

  defp normalize_value(%{} = value), do: normalize(value)
  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value("none"), do: :none
  defp normalize_value("complete"), do: :complete
  defp normalize_value("static_decision_package"), do: :static_decision_package
  defp normalize_value("blocking"), do: :blocking
  defp normalize_value("warning"), do: :warning
  defp normalize_value("passed"), do: :passed
  defp normalize_value("blocked"), do: :blocked
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "status" -> :status
      "package_kind" -> :package_kind
      "authority_effect" -> :authority_effect
      "creates_contract_lock?" -> :creates_contract_lock?
      "creates_contract_lock" -> :creates_contract_lock?
      "creates_approval?" -> :creates_approval?
      "creates_approval" -> :creates_approval?
      "creates_ready_slice?" -> :creates_ready_slice?
      "creates_ready_slice" -> :creates_ready_slice?
      "implementer_launched?" -> :implementer_launched?
      "implementer_launched" -> :implementer_launched?
      "rule_key" -> :rule_key
      "severity" -> :severity
      "subject_key" -> :subject_key
      "message" -> :message
      _ -> key
    end
  end

  defp get(map, key), do: Map.get(map, key)
  defp present?(value), do: not is_nil(value)
  defp truthy?(value), do: value in [true, "true"]
end
