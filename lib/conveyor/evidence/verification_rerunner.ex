defmodule Conveyor.Evidence.VerificationRerunner do
  @moduledoc """
  Independently reruns verification suites and parses structured test results.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.VerificationSuite
  alias Conveyor.TestResultAdapter

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{status: :passed | :failed, suites: [map()]}
    @enforce_keys [:status, :suites]
    defstruct [:status, :suites]
  end

  @suite_kinds [:baseline_regression, :acceptance_locked]

  @spec run!(RunSpec.t(), keyword()) :: Result.t()
  def run!(%RunSpec{} = run_spec, opts \\ []) do
    suites =
      run_spec.slice_id
      |> suites()
      |> Enum.map(&run_suite(&1, opts))

    status =
      if Enum.all?(suites, &(&1["status"] in ["passed", "passed_with_warning"])),
        do: :passed,
        else: :failed

    %Result{status: status, suites: suites}
  end

  defp suites(slice_id) do
    VerificationSuite
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id and &1.suite_kind in @suite_kinds))
  end

  defp run_suite(suite, opts) do
    commands = Enum.map(suite.command_specs, &run_command(&1, suite, opts))
    status = suite_status(commands)

    %{
      "suite_id" => suite.id,
      "key" => suite.key,
      "suite_kind" => Atom.to_string(suite.suite_kind),
      "status" => status,
      "commands" => commands
    }
  end

  defp run_command(command_spec, suite, opts) do
    attempts =
      command_spec
      |> repeat()
      |> then(
        &Enum.map(1..&1, fn attempt_no -> run_attempt(command_spec, suite, attempt_no, opts) end)
      )

    %{
      "key" => value(command_spec, "key"),
      "argv" => value(command_spec, "argv"),
      "status" => command_status(attempts, flake_policy(command_spec)),
      "classification" => classification(attempts),
      "attempts" => attempts
    }
  end

  defp run_attempt(command_spec, suite, attempt_no, opts) do
    runner =
      Keyword.get(opts, :runner, fn _command -> %{exit_code: 0, stdout: "", stderr: ""} end)

    case run_with_infra_retries(runner, command_spec) do
      {:ok, result, infra_retries} ->
        output = result_value(result, :stdout, "")
        exit_code = result_value(result, :exit_code, 0)

        tests =
          result_format(command_spec, suite)
          |> TestResultAdapter.parse!(output,
            test_id: value(command_spec, "key"),
            exit_code: exit_code
          )
          |> Enum.map(&test_result_map/1)

        %{
          "attempt_no" => attempt_no,
          "exit_code" => exit_code,
          "infra_retries" => infra_retries,
          "status" =>
            if(exit_code == 0 and Enum.all?(tests, &(&1["status"] != "failed")),
              do: "passed",
              else: "failed"
            ),
          "tests" => tests
        }

      {:error, reason, infra_retries} ->
        %{
          "attempt_no" => attempt_no,
          "exit_code" => nil,
          "infra_retries" => infra_retries,
          "status" => "infra_failed",
          "tests" => [],
          "error" => inspect(reason)
        }
    end
  end

  defp run_with_infra_retries(runner, command_spec) do
    policy = infra_retry_policy(command_spec)
    max_retries = Map.get(policy, "max_retries", 0)
    retry_on = Map.get(policy, "retry_on", [])
    do_run_with_infra_retries(runner, command_spec, max_retries, retry_on, 0)
  end

  defp do_run_with_infra_retries(runner, command_spec, remaining, retry_on, retries) do
    case runner.(command_spec) do
      %{error: reason} when remaining > 0 ->
        if to_string(reason) in retry_on do
          do_run_with_infra_retries(runner, command_spec, remaining - 1, retry_on, retries + 1)
        else
          {:error, reason, retries}
        end

      %{error: reason} ->
        {:error, reason, retries}

      result ->
        {:ok, result, retries}
    end
  end

  defp command_status(attempts, flake_policy) do
    cond do
      Enum.all?(attempts, &(&1["status"] == "passed")) ->
        "passed"

      flaky?(attempts) and flake_policy in ["quarantine", "allow_with_warning"] ->
        "passed_with_warning"

      true ->
        "failed"
    end
  end

  defp suite_status(commands) do
    if Enum.all?(commands, &(&1["status"] in ["passed", "passed_with_warning"])) do
      "passed"
    else
      "failed"
    end
  end

  defp classification(attempts) do
    if flaky?(attempts), do: "flake", else: "stable"
  end

  defp flaky?(attempts) do
    attempts
    |> Enum.map(& &1["status"])
    |> Enum.uniq()
    |> length()
    |> Kernel.>(1)
  end

  defp test_result_map(test) do
    %{
      "id" => test.id,
      "name" => test.name,
      "status" => Atom.to_string(test.status),
      "message" => test.message
    }
  end

  defp repeat(command_spec), do: value(command_spec, "repeat", 1)
  defp flake_policy(command_spec), do: value(command_spec, "flake_policy", "fail_closed")
  defp infra_retry_policy(command_spec), do: value(command_spec, "infra_retry_policy", %{})

  defp result_format(command_spec, suite),
    do: value(command_spec, "result_format", suite.result_format)

  defp value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, String.to_atom(key), default))
  end

  defp result_value(result, key, default) when is_map(result) do
    Map.get(result, key, Map.get(result, Atom.to_string(key), default))
  end
end
