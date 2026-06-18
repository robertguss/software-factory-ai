defmodule Conveyor.BaselineHealth do
  @moduledoc """
  Runs baseline regression suites against a clean base workspace.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.VerificationSuite

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{status: :passed | :failed, suites: [map()]}
    @enforce_keys [:status, :suites]
    defstruct [:status, :suites]
  end

  @spec run!(RunSpec.t(), keyword()) :: Result.t()
  def run!(%RunSpec{} = run_spec, opts \\ []) do
    suites =
      run_spec.slice_id
      |> baseline_suites()
      |> Enum.map(&run_suite(&1, opts))

    status =
      if Enum.all?(suites, &(&1["status"] == "passed")) do
        :passed
      else
        :failed
      end

    %Result{status: status, suites: suites}
  end

  defp baseline_suites(slice_id) do
    VerificationSuite
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id and &1.suite_kind == :baseline_regression))
  end

  defp run_suite(suite, opts) do
    command_results = Enum.map(suite.command_specs, &run_command(&1, opts))
    passed? = Enum.all?(command_results, &(&1["exit_code"] == 0))

    %{
      "suite_id" => suite.id,
      "key" => suite.key,
      "status" => if(passed?, do: "passed", else: "failed"),
      "commands" => command_results
    }
  end

  defp run_command(command_spec, opts) do
    runner =
      Keyword.get(opts, :runner, fn _command -> %{exit_code: 0, stdout: "", stderr: ""} end)

    result = runner.(command_spec)

    %{
      "argv" => command_spec["argv"] || command_spec[:argv],
      "exit_code" => result_value(result, :exit_code),
      "stdout" => result_value(result, :stdout, ""),
      "stderr" => result_value(result, :stderr, "")
    }
  end

  defp result_value(result, key, default \\ nil)
  defp result_value(result, key, default) when is_map(result), do: Map.get(result, key, default)
end
