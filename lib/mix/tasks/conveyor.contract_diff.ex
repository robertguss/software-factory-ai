defmodule Mix.Tasks.Conveyor.ContractDiff do
  @moduledoc """
  Prints a classified contract diff.

      mix conveyor.contract_diff --old OLD_JSON --new NEW_JSON
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.ContractEvolution

  @shortdoc "Classify contract changes before rerun"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_opts!(args)
    old = opts |> Keyword.fetch!(:old) |> read_json!()
    new = opts |> Keyword.fetch!(:new) |> read_json!()
    diff = ContractEvolution.diff(old, new)

    %{
      "schema_version" => "conveyor.contract_diff@1",
      "classifications" => Enum.map(diff.classifications, &Atom.to_string/1),
      "changed" => diff.changed?,
      "automatic_rerun_allowed" => diff.automatic_rerun_allowed?,
      "requires_human_decision" => diff.requires_human_decision?
    }
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  defp parse_opts!(args) do
    {opts, remaining, invalid} = OptionParser.parse(args, strict: [old: :string, new: :string])

    if remaining != [] or invalid != [] or is_nil(opts[:old]) or is_nil(opts[:new]) do
      Mix.raise(usage())
    end

    opts
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()

  defp usage do
    "usage: mix conveyor.contract_diff --old OLD_JSON --new NEW_JSON"
  end

  defp exit_fun do
    Process.get(:conveyor_contract_diff_exit_fun, &System.halt/1)
  end
end
