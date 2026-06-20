defmodule Mix.Tasks.Conveyor.Run do
  @moduledoc """
  Runs a normalized Conveyor plan through the production width-1 loop.

      mix conveyor.run PLAN.md [--adapter codex|reference_solution] [--workspace PATH]
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Planning.PlanRunner

  @shortdoc "Run a Conveyor plan through the serial production loop"

  @impl Mix.Task
  def run([plan_path | args]) do
    Mix.Task.run("app.start")
    opts = parse_opts!(args)
    adapter = adapter!(Keyword.get(opts, :adapter, "codex"))

    result =
      PlanRunner.run!(
        plan_path,
        workspace_path: Keyword.get(opts, :workspace),
        blob_root: Keyword.get(opts, :blob_root),
        agent_adapter: adapter
      )

    result
    |> summary()
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(exit_code(result.serial_result.status))
  end

  def run(_args), do: Mix.raise(usage())

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [adapter: :string, workspace: :string, blob_root: :string]
      )

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    opts
  end

  defp adapter!("codex"), do: Conveyor.AgentRunner.Codex
  defp adapter!("reference_solution"), do: Conveyor.AgentRunner.ReferenceSolution

  defp adapter!(adapter) do
    Mix.raise("unsupported --adapter #{inspect(adapter)} (expected codex|reference_solution)")
  end

  defp summary(result) do
    serial_result = result.serial_result
    report = serial_result.report

    %{
      "status" => Atom.to_string(serial_result.status),
      "plan_path" => result.plan_path,
      "adapter" => adapter_name(result.adapter),
      "slice_count" => map_size(result.slices_by_stable_key),
      "serial_order" => serial_result.order,
      "event_count" => length(serial_result.events),
      "first_pass_gate_success_rate" => report["first_pass_gate_success_rate"],
      "eventual_gate_success_rate" => report["eventual_gate_success_rate"],
      "replay_fidelity" => report["replay_fidelity"]
    }
  end

  defp adapter_name(Conveyor.AgentRunner.Codex), do: "codex"
  defp adapter_name(Conveyor.AgentRunner.ReferenceSolution), do: "reference_solution"
  defp adapter_name(adapter), do: inspect(adapter)

  defp exit_code(:passed), do: ExitCodes.fetch!(:success)
  defp exit_code(:halted), do: ExitCodes.fetch!(:deterministic_gate_failed)

  defp usage do
    "usage: mix conveyor.run PLAN.md [--adapter codex|reference_solution] [--workspace PATH]"
  end

  defp exit_fun do
    Process.get(:conveyor_run_exit_fun, &System.halt/1)
  end
end
