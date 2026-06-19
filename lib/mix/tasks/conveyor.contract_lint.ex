defmodule Mix.Tasks.Conveyor.ContractLint do
  @moduledoc """
  Runs deterministic, non-authorizing lint on a compiler contract or agent brief.

      mix conveyor.contract_lint agent_brief.json --format human|json|sarif
  """

  use Mix.Task

  alias Conveyor.Planning.PlanLint
  alias Conveyor.Planning.PlanLintCLI

  @shortdoc "Lint a contract without agents or execution authority"

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
        Mix.raise("usage: mix conveyor.contract_lint agent_brief.json --format human|json|sarif")
    end
  end

  defp exit_fun do
    Process.get(:conveyor_contract_lint_exit_fun, &System.halt/1)
  end
end
