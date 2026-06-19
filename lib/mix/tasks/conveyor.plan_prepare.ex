defmodule Mix.Tasks.Conveyor.PlanPrepare do
  @moduledoc """
  Builds a static, non-authorizing plan preparation package.

      mix conveyor.plan_prepare PLAN.md --no-agents --format human|json
  """

  use Mix.Task

  alias Conveyor.Planning.PlanLint
  alias Conveyor.Planning.PlanLintCLI

  @shortdoc "Prepare a plan without agents or execution authority"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [format: :string, no_agents: :boolean])

    with [] <- invalid,
         [path] <- rest,
         true <- Keyword.get(opts, :no_agents, false),
         {:ok, format} <- prepare_format(Keyword.get(opts, :format)),
         {:ok, contract} <- PlanLintCLI.load_contract(path) do
      result = PlanLint.prepare(contract)
      result |> render(format) |> PlanLintCLI.print_result(format)
      exit_fun().(PlanLintCLI.exit_code(result))
    else
      {:error, error} ->
        Mix.shell().error(error)
        exit_fun().(PlanLintCLI.malformed_exit_code())

      _ ->
        Mix.raise("usage: mix conveyor.plan_prepare PLAN.md --no-agents --format human|json")
    end
  end

  defp prepare_format(nil), do: {:ok, :human}
  defp prepare_format("human"), do: {:ok, :human}
  defp prepare_format("json"), do: {:ok, :json}
  defp prepare_format(other), do: {:error, "unsupported --format: #{other} (expected human|json)"}

  defp render(result, :json), do: result

  defp render(result, :human) do
    [
      "plan_prepare: #{result.status}",
      "Mode: NON-authorizing",
      "No agents: #{result.no_agents}",
      "Provider credentials required: #{result.provider_credentials_required}",
      PlanLint.render(result.lint, format: :human)
    ]
    |> Enum.join("\n")
  end

  defp exit_fun do
    Process.get(:conveyor_plan_prepare_exit_fun, &System.halt/1)
  end
end
