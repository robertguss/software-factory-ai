defmodule Conveyor.Evidence.AcceptanceMapper do
  @moduledoc """
  Maps acceptance criteria to structured verification test results.
  """

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            status: :passed | :failed,
            acceptance_results: [map()],
            findings: [map()]
          }
    @enforce_keys [:status, :acceptance_results, :findings]
    defstruct [:status, :acceptance_results, :findings]
  end

  @spec map!([map()], map() | struct()) :: Result.t()
  def map!(acceptance_criteria, verification_result) when is_list(acceptance_criteria) do
    test_results = test_results_by_id(verification_result)

    acceptance_results =
      Enum.map(acceptance_criteria, &map_criterion(&1, test_results))

    findings = Enum.flat_map(acceptance_results, &findings_for_result/1)

    status =
      if findings == [] and Enum.all?(acceptance_results, &(&1["evidence_status"] == "passed")),
        do: :passed,
        else: :failed

    %Result{status: status, acceptance_results: acceptance_results, findings: findings}
  end

  defp map_criterion(criterion, test_results) do
    required_refs = Map.get(criterion, "required_test_refs", [])
    required_results = Enum.map(required_refs, &required_result(&1, test_results))
    evidence_status = evidence_status(required_results)

    criterion
    |> Map.put("evidence_status", evidence_status)
    |> Map.put("evidence_refs", evidence_refs(required_results))
    |> Map.put("required_test_results", required_results)
  end

  defp required_result(ref, test_results) do
    case Map.get(test_results, ref) do
      nil ->
        %{"id" => ref, "status" => "missing", "evidence_ref" => nil}

      result ->
        result
        |> Map.take(["id", "name", "status", "message"])
        |> Map.put("evidence_ref", "test-result:#{ref}")
    end
  end

  defp evidence_status([]), do: "missing"

  defp evidence_status(required_results) do
    cond do
      Enum.any?(required_results, &(&1["status"] == "missing")) -> "missing"
      Enum.any?(required_results, &(&1["status"] == "failed")) -> "failed"
      Enum.any?(required_results, &(&1["status"] == "skipped")) -> "skipped"
      true -> "passed"
    end
  end

  defp evidence_refs(required_results) do
    required_results
    |> Enum.map(& &1["evidence_ref"])
    |> Enum.reject(&is_nil/1)
  end

  defp findings_for_result(%{"evidence_status" => "missing"} = result) do
    result
    |> blocked_refs("missing")
    |> Enum.map(&finding(result, "missing_required_test", "Required test result is missing", &1))
  end

  defp findings_for_result(%{"evidence_status" => "skipped"} = result) do
    result
    |> blocked_refs("skipped")
    |> Enum.map(&finding(result, "skipped_required_test", "Required test was skipped", &1))
  end

  defp findings_for_result(_result), do: []

  defp blocked_refs(result, status) do
    result
    |> Map.fetch!("required_test_results")
    |> Enum.filter(&(&1["status"] == status))
    |> Enum.map(& &1["id"])
  end

  defp finding(result, category, message, test_ref) do
    %{
      "severity" => "blocking",
      "category" => category,
      "message" => message,
      "acceptance_criterion_id" => Map.get(result, "id"),
      "test_ref" => test_ref
    }
  end

  defp test_results_by_id(%{suites: suites}), do: test_results_by_id(%{"suites" => suites})

  defp test_results_by_id(%{"suites" => suites}) do
    suites
    |> Enum.flat_map(&suite_tests/1)
    |> Map.new(fn test -> {test["id"], test} end)
  end

  defp suite_tests(suite) do
    suite
    |> Map.get("commands", [])
    |> Enum.flat_map(fn command ->
      command
      |> Map.get("attempts", [])
      |> Enum.flat_map(&Map.get(&1, "tests", []))
    end)
  end
end
