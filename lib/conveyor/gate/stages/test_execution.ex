defmodule Conveyor.Gate.Stages.TestExecution do
  @moduledoc """
  Gate stage 7: reruns baseline and locked acceptance suites.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Evidence.VerificationRerunner
  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.TestPackCalibration
  alias Conveyor.Gate.StageResult

  @impl true
  def run(context, _opts \\ []) do
    result = verification_result(context)
    calibration = acceptance_calibration(context, value(context, :run_spec))
    findings = findings(result, calibration, context)

    %StageResult{
      key: "test_execution",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(result, calibration),
      input_digests: %{
        "verification_result_sha256" => digest(result),
        "calibration_sha256" => digest(calibration)
      }
    }
  end

  defp verification_result(context) do
    case value(context, :verification_result) do
      nil ->
        run_spec_result(context)

      result ->
        normalize_result(result)
    end
  end

  defp run_spec_result(context) do
    case value(context, :run_spec) do
      %RunSpec{} = run_spec ->
        opts = verification_opts(context)

        VerificationRerunner.run!(run_spec, opts) |> normalize_result()

      _run_spec ->
        %{"status" => "missing", "suites" => []}
    end
  end

  defp verification_opts(context) do
    case value(context, :verification_runner) || value(context, :runner) do
      nil -> []
      runner -> [runner: runner]
    end
  end

  defp acceptance_calibration(context, run_spec) do
    calibration =
      value(context, :test_pack_calibration) || value(context, :acceptance_calibration) ||
        persisted_calibration(run_spec)

    normalize_calibration(calibration)
  end

  defp normalize_calibration(%TestPackCalibration{} = calibration) do
    %{
      "id" => calibration.id,
      "status" => Atom.to_string(calibration.status),
      "expected_failures" => calibration.expected_failures,
      "unexpected_passes" => calibration.unexpected_passes,
      "unexpected_failures" => calibration.unexpected_failures,
      "result_ref" => calibration.result_ref,
      "base_commit" => calibration.base_commit
    }
  end

  defp normalize_calibration(calibration), do: calibration

  defp persisted_calibration(%RunSpec{} = run_spec) do
    TestPackCalibration
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_spec_id == run_spec.id and &1.base_commit == run_spec.base_commit))
    |> Enum.sort_by(&DateTime.to_unix(&1.calibrated_at, :microsecond), :desc)
    |> List.first()
  end

  defp persisted_calibration(_run_spec), do: nil

  defp normalize_result(%VerificationRerunner.Result{} = result) do
    %{"status" => Atom.to_string(result.status), "suites" => result.suites}
  end

  defp normalize_result(%{status: _status} = result), do: stringify_keys(result)
  defp normalize_result(%{"status" => _status} = result), do: result
  defp normalize_result(_result), do: %{"status" => "missing", "suites" => []}

  defp findings(%{"status" => "missing"}, _calibration, _context) do
    [
      finding(
        "missing_verification_evidence",
        "Verification rerun evidence is required for gate tests."
      )
    ]
  end

  defp findings(result, calibration, context) do
    suites = value(result, :suites) || []

    []
    |> require_suite(suites, "baseline_regression")
    |> require_suite(suites, "acceptance_locked")
    |> Kernel.++(empty_acceptance_findings(suites))
    |> Kernel.++(failed_suite_findings(suites))
    |> Kernel.++(calibration_findings(suites, calibration))
    |> Kernel.++(flake_findings(suites, context))
    |> Kernel.++(result_status_findings(result))
  end

  # dr1m.7 backstop: a present acceptance_locked suite that ran ZERO tests fails the gate
  # even if it falsely reported "passed". "Zero tests" = no commands, or the commands DID
  # enumerate per-test results and the total is zero. A non-enumerating representation
  # (status-only commands, no "tests" key) is NOT treated as empty (stdout/exit-code
  # suites and abstractions keep their status).
  defp empty_acceptance_findings(suites) do
    suites
    |> Enum.filter(&(value(&1, :suite_kind) == "acceptance_locked"))
    |> Enum.filter(&acceptance_ran_zero_tests?/1)
    |> Enum.map(fn suite ->
      finding(
        "empty_acceptance_suite",
        "Locked acceptance suite ran zero tests; the slice cannot be verified.",
        suite
      )
    end)
  end

  defp acceptance_ran_zero_tests?(suite) do
    commands = List.wrap(value(suite, :commands))
    attempts = Enum.flat_map(commands, &(value(&1, :attempts) || []))
    enumerated = Enum.filter(attempts, &enumerates_tests?/1)

    commands == [] or (enumerated != [] and Enum.all?(enumerated, &(test_list(&1) == [])))
  end

  defp enumerates_tests?(attempt) when is_map(attempt),
    do: Map.has_key?(attempt, "tests") or Map.has_key?(attempt, :tests)

  defp enumerates_tests?(_attempt), do: false

  defp test_list(attempt), do: value(attempt, :tests) || []

  defp require_suite(findings, suites, suite_kind) do
    if Enum.any?(suites, &(value(&1, :suite_kind) == suite_kind)) do
      findings
    else
      [finding("missing_#{suite_kind}", "#{suite_kind} suite evidence is required.") | findings]
    end
  end

  defp failed_suite_findings(suites) do
    suites
    |> Enum.filter(&(value(&1, :status) not in ["passed", "passed_with_warning"]))
    |> Enum.map(fn suite ->
      category =
        case value(suite, :suite_kind) do
          "baseline_regression" -> "baseline_regression_failed"
          "acceptance_locked" -> "acceptance_locked_failed"
          _other -> "verification_suite_failed"
        end

      finding(category, "Required verification suite failed.", suite)
    end)
  end

  defp calibration_findings(suites, calibration) do
    if Enum.any?(suites, &(value(&1, :suite_kind) == "acceptance_locked")) do
      cond do
        is_nil(calibration) ->
          [
            finding(
              "missing_acceptance_calibration",
              "Locked acceptance suite requires a valid base red calibration."
            )
          ]

        value(calibration, :status) not in [:valid, "valid"] ->
          [
            finding(
              "invalid_acceptance_calibration",
              "Locked acceptance calibration is invalid."
            )
          ]

        List.wrap(value(calibration, :expected_failures)) == [] ->
          [
            finding(
              "missing_expected_acceptance_red",
              "Locked acceptance calibration did not record expected red failures on base."
            )
          ]

        true ->
          []
      end
    else
      []
    end
  end

  defp flake_findings(suites, context) do
    approved? = value(context, :flake_quarantine_approved) == true

    suites
    |> Enum.flat_map(&(value(&1, :commands) || []))
    |> Enum.filter(&flake?/1)
    |> Enum.reject(fn _command -> approved? end)
    |> Enum.map(fn command ->
      finding(
        "unapproved_flake_quarantine",
        "Flaky verification command requires a human quarantine decision.",
        command
      )
    end)
  end

  defp result_status_findings(%{"status" => "failed"} = result) do
    if failed_suite_findings(value(result, :suites) || []) == [] do
      [finding("verification_failed", "Verification rerunner reported failure.")]
    else
      []
    end
  end

  defp result_status_findings(_result), do: []

  defp flake?(command) do
    value(command, :classification) == "flake" or value(command, :status) == "passed_with_warning"
  end

  defp finding(category, message, subject \\ nil) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "key" => value(subject, :key),
      "suite_kind" => value(subject, :suite_kind),
      "status" => value(subject, :status)
    }
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp evidence_refs(result, calibration) do
    suites =
      result
      |> value(:suites)
      |> List.wrap()
      |> Enum.map(&value(&1, :suite_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&"verification-suites/#{&1}")

    suites ++ Enum.reject([value(calibration, :result_ref)], &is_nil/1)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_nested(value)} end)
  end

  defp stringify_nested(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested(value) when is_list(value), do: Enum.map(value, &stringify_nested/1)
  defp stringify_nested(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_nested(value), do: value

  defp digest(value), do: Conveyor.CanonicalJson.digest(value)

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
