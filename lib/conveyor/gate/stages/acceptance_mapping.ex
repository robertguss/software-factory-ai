defmodule Conveyor.Gate.Stages.AcceptanceMapping do
  @moduledoc """
  Gate stage 8: verifies every acceptance criterion has passing evidence.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Evidence.AcceptanceMapper
  alias Conveyor.Gate.StageResult

  @impl true
  def run(context, _opts \\ []) do
    acceptance = acceptance_result(context)
    allowed_skips = value(context, :allowed_skipped_acceptance_refs) || []
    findings = findings(acceptance, allowed_skips)

    %StageResult{
      key: "acceptance_mapping",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(acceptance),
      input_digests: %{"acceptance_mapping_sha256" => digest(acceptance)}
    }
  end

  defp acceptance_result(context) do
    cond do
      result = value(context, :acceptance_mapping) ->
        normalize_result(result)

      results = value(context, :acceptance_results) ->
        %{"status" => "unknown", "acceptance_results" => results, "findings" => []}

      criteria = acceptance_criteria(context) ->
        context
        |> value(:verification_result)
        |> then(&AcceptanceMapper.map!(criteria, &1 || %{"suites" => []}))
        |> normalize_result()

      true ->
        %{"status" => "missing", "acceptance_results" => [], "findings" => []}
    end
  end

  defp acceptance_criteria(context) do
    value(context, :acceptance_criteria) ||
      value(value(context, :agent_brief), :acceptance_criteria)
  end

  defp normalize_result(%AcceptanceMapper.Result{} = result) do
    %{
      "status" => Atom.to_string(result.status),
      "acceptance_results" => result.acceptance_results,
      "findings" => result.findings
    }
  end

  defp normalize_result(%{status: _status} = result), do: stringify_keys(result)
  defp normalize_result(%{"status" => _status} = result), do: result

  defp findings(%{"status" => "missing"}, _allowed_skips) do
    [
      finding(
        "missing_acceptance_mapping",
        "Acceptance mapping evidence is required."
      )
    ]
  end

  defp findings(%{"acceptance_results" => []}, _allowed_skips) do
    [
      finding(
        "missing_acceptance_mapping",
        "Acceptance mapping contains no acceptance criteria."
      )
    ]
  end

  defp findings(%{"acceptance_results" => results, "findings" => mapper_findings}, allowed_skips) do
    mapper_findings ++ Enum.flat_map(results, &result_findings(&1, allowed_skips))
  end

  defp result_findings(%{"evidence_status" => "passed"}, _allowed_skips), do: []

  defp result_findings(%{"evidence_status" => "skipped"} = result, allowed_skips) do
    id = value(result, :id)

    if id in allowed_skips do
      []
    else
      [
        finding(
          "skipped_acceptance_evidence",
          "Acceptance criterion has skipped evidence.",
          result
        )
      ]
    end
  end

  defp result_findings(%{"evidence_status" => "missing"} = result, _allowed_skips) do
    [
      finding(
        "missing_acceptance_evidence",
        "Acceptance criterion is missing required evidence.",
        result
      )
    ]
  end

  defp result_findings(%{"evidence_status" => "failed"} = result, _allowed_skips) do
    [
      finding(
        "failed_acceptance_evidence",
        "Acceptance criterion has failed evidence.",
        result
      )
    ]
  end

  defp result_findings(result, _allowed_skips) do
    [
      finding(
        "unknown_acceptance_evidence",
        "Acceptance criterion has an unknown evidence status.",
        result
      )
    ]
  end

  defp finding(category, message, result \\ nil) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "acceptance_criterion_id" => value(result, :id),
      "evidence_status" => value(result, :evidence_status)
    }
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp evidence_refs(acceptance) do
    acceptance
    |> value(:acceptance_results)
    |> List.wrap()
    |> Enum.flat_map(&(value(&1, :evidence_refs) || []))
    |> Enum.uniq()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_nested(value)} end)
  end

  defp stringify_nested(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested(value) when is_list(value), do: Enum.map(value, &stringify_nested/1)
  defp stringify_nested(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_nested(value), do: value

  defp digest(value) do
    "sha256:" <>
      (:sha256
       |> :crypto.hash(:erlang.term_to_binary(value))
       |> Base.encode16(case: :lower))
  end

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
