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

    @type t :: %__MODULE__{
            status: :passed | :failed,
            suites: [map()],
            reproducibility: map() | nil
          }
    @enforce_keys [:status, :suites]
    defstruct [:status, :suites, :reproducibility]
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

  @spec run_reproducible!(RunSpec.t(), keyword()) :: Result.t()
  def run_reproducible!(%RunSpec{} = run_spec, opts \\ []) do
    agent_runner = Keyword.fetch!(opts, :agent_runner)
    gate_runner = Keyword.fetch!(opts, :gate_runner)
    run_opts = Keyword.drop(opts, [:agent_runner, :gate_runner])

    agent_result = run!(run_spec, Keyword.put(run_opts, :runner, agent_runner))
    gate_result = run!(run_spec, Keyword.put(run_opts, :runner, gate_runner))
    reproducibility = reproducibility(agent_result, gate_result)

    status =
      if agent_result.status == :passed and gate_result.status == :passed and
           reproducibility["status"] == "passed" do
        :passed
      else
        :failed
      end

    %Result{status: status, suites: gate_result.suites, reproducibility: reproducibility}
  end

  defp suites(slice_id) do
    VerificationSuite
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id and &1.suite_kind in @suite_kinds))
  end

  defp reproducibility(agent_result, gate_result) do
    agent_digest = digest(agent_result.suites)
    gate_digest = digest(gate_result.suites)

    findings =
      if agent_digest == gate_digest do
        []
      else
        [
          %{
            "category" => "clean_container_divergence",
            "severity" => "blocking",
            "agent_status" => Atom.to_string(agent_result.status),
            "gate_status" => Atom.to_string(gate_result.status),
            "agent_sha256" => agent_digest,
            "gate_sha256" => gate_digest
          }
        ]
      end

    %{
      "status" => if(findings == [], do: "passed", else: "failed"),
      "agent_status" => Atom.to_string(agent_result.status),
      "gate_status" => Atom.to_string(gate_result.status),
      "agent_sha256" => agent_digest,
      "gate_sha256" => gate_digest,
      "findings" => findings
    }
  end

  defp digest(value) do
    value
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp run_suite(suite, opts) do
    commands = Enum.map(suite.command_specs, &run_command(&1, suite, opts))
    status = suite_status(suite.suite_kind, commands)

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

  # dr1m.7: an acceptance_locked suite that ran ZERO tests cannot pass — even if every
  # (empty) command reported "passed". "Zero tests" means either no commands at all, or
  # the commands DID enumerate test results and the total is zero (a test-enumerating
  # format that selected nothing). A non-enumerating command (no "tests" key) is left to
  # its own status so stdout/exit-code suites are unaffected.
  defp suite_status(:acceptance_locked, commands) do
    if acceptance_ran_zero_tests?(commands), do: "failed", else: suite_status(nil, commands)
  end

  defp suite_status(_kind, commands) do
    if Enum.all?(commands, &(&1["status"] in ["passed", "passed_with_warning"])) do
      "passed"
    else
      "failed"
    end
  end

  defp acceptance_ran_zero_tests?(commands) do
    attempts = Enum.flat_map(commands, &(value(&1, "attempts") || []))
    enumerated = Enum.filter(attempts, &Map.has_key?(&1, "tests"))

    commands == [] or (enumerated != [] and Enum.all?(enumerated, &((&1["tests"] || []) == [])))
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

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
