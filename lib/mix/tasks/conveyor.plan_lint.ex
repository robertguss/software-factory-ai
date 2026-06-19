defmodule Mix.Tasks.Conveyor.PlanLint do
  @moduledoc """
  Runs deterministic, non-authorizing plan lint.

      mix conveyor.plan_lint PLAN.md --format human|json|sarif
  """

  use Mix.Task

  alias Conveyor.Planning.PlanLint
  alias Conveyor.Planning.PlanLintCLI

  @shortdoc "Lint a plan without agents or execution authority"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [format: :string])

    with [] <- invalid,
         [path] <- rest,
         format <- PlanLintCLI.parse_format(Keyword.get(opts, :format)),
         {:ok, contract} <- PlanLintCLI.load_contract(path) do
      result = PlanLint.lint(contract)
      result |> PlanLint.render(format: format) |> PlanLintCLI.print_result(format)
      exit_fun().(PlanLintCLI.exit_code(result))
    else
      {:error, error} ->
        Mix.shell().error(error)
        exit_fun().(PlanLintCLI.malformed_exit_code())

      _ ->
        Mix.raise("usage: mix conveyor.plan_lint PLAN.md --format human|json|sarif")
    end
  end

  defp exit_fun do
    Process.get(:conveyor_plan_lint_exit_fun, &System.halt/1)
  end
end
