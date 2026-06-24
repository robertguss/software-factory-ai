defmodule Mix.Tasks.Conveyor.Run do
  @moduledoc """
  Runs a normalized Conveyor plan through the production width-1 loop.

      mix conveyor.run PLAN.md [--adapter codex|reference_solution] [--workspace PATH] [--in-place]

  By default the run operates on an **isolated copy** of `--workspace`: the loop
  resets and commits as it goes, so it must never mutate a directory you care
  about (there is no blast-radius container yet). The source dir is left
  untouched and the isolated copy's path is printed. Pass `--in-place` to run
  directly in `--workspace` (e.g. a throwaway dir you have already staged).
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
    workspace = resolve_workspace!(opts)

    result =
      PlanRunner.run!(
        plan_path,
        workspace_path: workspace,
        blob_root: Keyword.get(opts, :blob_root),
        agent_adapter: adapter
      )

    result
    |> summary()
    |> Map.put("workspace", workspace)
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(exit_code(result.serial_result.status))
  end

  def run(_args), do: Mix.raise(usage())

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [adapter: :string, workspace: :string, blob_root: :string, in_place: :boolean]
      )

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    opts
  end

  # Isolate the run from the user's directory: the loop resets/cleans/commits the
  # workspace, so by default we copy `--workspace` to a throwaway location and run
  # there, leaving the source untouched. `--in-place` opts out. No `--workspace`
  # leaves PlanRunner's default (the plan's own dir) unchanged.
  defp resolve_workspace!(opts) do
    case Keyword.get(opts, :workspace) do
      nil ->
        nil

      workspace ->
        if Keyword.get(opts, :in_place, false), do: workspace, else: isolate!(workspace)
    end
  end

  defp isolate!(source) do
    source = Path.expand(source)

    unless File.dir?(source) do
      Mix.raise("--workspace #{source} is not a directory")
    end

    dest =
      Path.join([
        System.tmp_dir!(),
        "conveyor-run-workspaces",
        "#{Path.basename(source)}-#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(dest)
    File.mkdir_p!(Path.dirname(dest))
    File.cp_r!(source, dest)
    # Human diagnostic on stderr — stdout stays pure JSON (consumers Jason.decode! it).
    IO.puts(:stderr, "isolated workspace: #{dest}  (source #{source} left untouched)")
    dest
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
  # M3: a :partial run advanced past ≥1 parked/skipped slice — non-zero so an
  # unattended caller still treats "not fully green" as needs-attention. (Refining
  # the parked-vs-hard-fail exit distinction is tracked in dr1m.6.1.)
  defp exit_code(:partial), do: ExitCodes.fetch!(:deterministic_gate_failed)

  defp usage do
    "usage: mix conveyor.run PLAN.md [--adapter codex|reference_solution] [--workspace PATH] [--in-place]"
  end

  defp exit_fun do
    Process.get(:conveyor_run_exit_fun, &System.halt/1)
  end
end
