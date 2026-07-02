defmodule Conveyor.Verification.CommandSuiteRunner do
  @moduledoc """
  Generic `verification_result` producer (tt6v.1): runs a slice's locked `command_specs` through
  the `CommandRunner` seam and builds the `verification_result` map the gate consumes — the
  any-language counterpart to the pytest-specific `Eval.ToolchainRunner.verification_result/3`.

  Each locked command is executed (policy-checked), its output parsed by the declared
  `result_format`, and folded into a single `acceptance_locked` suite. An empty command set fails
  (dr1m.7: a zero-test acceptance suite must not vacuously pass). Deterministic: fixed suite/command
  order and a content digest over `{status, suites}`.
  """

  alias Conveyor.CanonicalJson
  alias Conveyor.TestResultAdapter
  alias Conveyor.Verification.CommandRunner

  @spec verification_result([map()], String.t(), struct(), keyword()) :: map()
  def verification_result(command_specs, workspace_root, policy, opts \\ []) do
    run = CommandRunner.runner(workspace_root, policy, opts)
    commands = Enum.map(command_specs, &run_command(&1, run))
    status = suite_status(commands)

    suites = [
      %{
        "suite_id" => "generic-acceptance_locked",
        "key" => "acceptance_locked",
        "suite_kind" => "acceptance_locked",
        "status" => status,
        "commands" => commands
      }
    ]

    result = %{"status" => status, "suites" => suites}
    Map.put(result, "result_digest", CanonicalJson.digest(result))
  end

  defp run_command(command_spec, run) do
    result = run.(command_spec)
    exit_code = result["exit_code"]

    tests =
      command_spec
      |> result_format()
      |> TestResultAdapter.parse!(result["stdout"] || "",
        test_id: value(command_spec, "key"),
        exit_code: exit_code
      )
      |> Enum.map(&test_map/1)

    status = command_status(exit_code, tests)

    %{
      "key" => value(command_spec, "key"),
      "argv" => value(command_spec, "argv"),
      "status" => status,
      "classification" => "stable",
      "attempts" => [
        %{
          "attempt_no" => 1,
          "exit_code" => exit_code,
          "infra_retries" => 0,
          "status" => status,
          "tests" => tests,
          "error" => nil
        }
      ]
    }
  end

  defp command_status(0, tests) do
    if Enum.all?(tests, &(&1["status"] != "failed")), do: "passed", else: "failed"
  end

  defp command_status(_nonzero, _tests), do: "failed"

  # dr1m.7: no locked acceptance commands => the suite cannot pass.
  defp suite_status([]), do: "failed"

  defp suite_status(commands) do
    if Enum.all?(commands, &(&1["status"] == "passed")), do: "passed", else: "failed"
  end

  defp test_map(test) do
    %{
      "id" => test.id,
      "name" => test.name,
      "status" => Atom.to_string(test.status),
      "message" => test.message
    }
  end

  defp result_format(command_spec), do: value(command_spec, "result_format") || "stdout"

  defp value(map, key), do: Map.get(map, key, Map.get(map, safe_atom(key)))

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :"#{key}__absent"
  end
end
