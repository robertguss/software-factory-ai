defmodule Conveyor.ContractForge.VerificationObligationDeriver do
  @moduledoc """
  Derives VerificationObligation projections from upgraded AgentBrief contracts.
  """

  @spec derive(map()) :: {:ok, [map()]} | {:error, [map()]}
  def derive(contract) when is_map(contract) do
    normalized = stringify_map(contract)
    acceptance_criteria = Map.get(normalized, "acceptance_criteria", [])
    findings = Enum.flat_map(acceptance_criteria, &acceptance_findings/1)

    if findings == [] do
      {:ok, Enum.map(acceptance_criteria, &obligation(normalized, &1))}
    else
      {:error, findings}
    end
  end

  defp acceptance_findings(ac) do
    if machine_checkable?(ac) and Map.get(ac, "falsifying_conditions", []) == [] do
      [
        %{
          rule_key: "acceptance_criterion_missing_falsifier",
          severity: :blocking,
          subject_key: Map.get(ac, "id"),
          message:
            "machine-checkable acceptance criteria require at least one falsifying condition"
        }
      ]
    else
      []
    end
  end

  defp obligation(contract, ac) do
    evidence_ref =
      ac
      |> Map.get("required_test_refs", [])
      |> List.first()

    %{
      "schema_version" => "conveyor.verification_obligation@1",
      "slice_id" => Map.fetch!(contract, "slice_id"),
      "acceptance_ref" => Map.fetch!(ac, "id"),
      "obligation_kind" => Map.get(ac, "verification_stage", "unit"),
      "required" => true,
      "evidence_requirement_ref" => evidence_ref || "falsifier:" <> Map.fetch!(ac, "id"),
      "status" => "pending"
    }
  end

  defp machine_checkable?(ac), do: Map.get(ac, "machine_checkable", true) in [true, "true"]

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value), do: value
end
