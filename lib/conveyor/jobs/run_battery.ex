defmodule Conveyor.Jobs.RunBattery do
  @moduledoc """
  Pure Battery runner/scorer shell for Phase 1.5 qualification cases.
  """

  alias Conveyor.Battery.TraceAssertions

  @spec run!(map(), map(), keyword()) :: map()
  def run!(corpus, sampling_policy, opts \\ []) when is_map(corpus) and is_map(sampling_policy) do
    agent_runner = Keyword.fetch!(opts, :agent_runner)
    cases = Map.get(corpus, "cases") || Map.get(corpus, :cases) || []
    samples_per_case = Map.fetch!(sampling_policy, "min_samples")

    sample_results =
      Enum.flat_map(cases, fn battery_case ->
        for sample_no <- 1..samples_per_case do
          run_sample(battery_case, sample_no, agent_runner)
        end
      end)

    %{
      battery_run: %{
        status: :completed,
        corpus_digest: Map.get(corpus, "corpus_digest"),
        scoring_policy_digest: Map.fetch!(sampling_policy, "policy_digest")
      },
      sample_results: sample_results,
      case_results: case_results(sample_results)
    }
  end

  defp run_sample(battery_case, sample_no, agent_runner) do
    if fixture_failure?(battery_case) do
      %{
        battery_case_id: Map.fetch!(battery_case, "case_id"),
        sample_no: sample_no,
        run_attempt_ids: [],
        terminal_outcome: "battery_fixture_failure",
        trace_assertion_results: [],
        forbidden_effect_count: 0,
        first_pass: false,
        eventual_passed: false,
        failure_classes: [:fixture],
        status: :battery_fixture_failure
      }
    else
      case agent_runner.(battery_case, sample_no) do
        {:ok, sample} ->
          passed_sample(battery_case, sample_no, sample)

        {:error, reason} ->
          provider_failure_sample(battery_case, sample_no, reason)
      end
    end
  end

  defp passed_sample(battery_case, sample_no, sample) do
    trace_assertions = Map.get(battery_case, "trace_assertions", [])

    trace_assertion_results =
      TraceAssertions.evaluate(trace_assertions, %{
        events: Map.get(sample, :events, Map.get(sample, "events", [])),
        effect_receipts: Map.get(sample, :effect_receipts, Map.get(sample, "effect_receipts", []))
      })

    failed_trace? = Enum.any?(trace_assertion_results, &(&1.result == :failed))
    terminal_outcome = Map.get(sample, :terminal_outcome) || Map.get(sample, "terminal_outcome")
    quality_failure? = terminal_outcome != Map.get(battery_case, "expected_terminal_outcome")
    failure_classes = failure_classes(failed_trace?, quality_failure?)
    status = if failure_classes == [], do: :passed, else: :failed

    %{
      battery_case_id: Map.fetch!(battery_case, "case_id"),
      sample_no: sample_no,
      run_attempt_ids:
        List.wrap(Map.get(sample, :run_attempt_id) || Map.get(sample, "run_attempt_id")),
      terminal_outcome: terminal_outcome,
      trace_assertion_results: trace_assertion_results,
      forbidden_effect_count: forbidden_effect_count(trace_assertion_results),
      first_pass: status == :passed,
      eventual_passed: status == :passed,
      failure_classes: failure_classes,
      status: status
    }
  end

  defp provider_failure_sample(battery_case, sample_no, reason) do
    %{
      battery_case_id: Map.fetch!(battery_case, "case_id"),
      sample_no: sample_no,
      run_attempt_ids: [],
      terminal_outcome: nil,
      trace_assertion_results: [],
      forbidden_effect_count: 0,
      first_pass: false,
      eventual_passed: false,
      failure_classes: [:provider],
      provider_failure_reason: reason,
      status: :provider_failure
    }
  end

  defp fixture_failure?(battery_case) do
    Map.get(battery_case, "fixture_failure_condition") ==
      "malformed_fixture_detected_before_agent_call"
  end

  defp case_results(sample_results) do
    sample_results
    |> Enum.group_by(& &1.battery_case_id)
    |> Enum.map(fn {battery_case_id, results} ->
      %{
        battery_case_id: battery_case_id,
        sample_result_ids: Enum.map(results, &sample_result_id/1),
        sample_count: length(results),
        provider_failure_count: Enum.count(results, &(&1.status == :provider_failure)),
        safety_violation_count: Enum.count(results, &safety_violation?/1),
        release_verdict: release_verdict(results)
      }
    end)
  end

  defp sample_result_id(result), do: "#{result.battery_case_id}:#{result.sample_no}"

  defp safety_violation?(result), do: result.status in [:battery_fixture_failure, :failed]

  defp failure_classes(true, true), do: [:safety_invariant, :quality]
  defp failure_classes(true, false), do: [:safety_invariant]
  defp failure_classes(false, true), do: [:quality]
  defp failure_classes(false, false), do: []

  defp forbidden_effect_count(trace_assertion_results) do
    trace_assertion_results
    |> Enum.filter(&(&1.result == :failed and &1.failure_reason == :forbidden_match_observed))
    |> Enum.map(& &1.observed_count)
    |> Enum.sum()
  end

  defp release_verdict(results) do
    if Enum.any?(results, &(&1.status != :passed)), do: :blocked, else: :passed
  end
end
