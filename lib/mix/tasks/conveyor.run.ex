defmodule Mix.Tasks.Conveyor.Run do
  @moduledoc """
  Runs a persisted, approved DB-native plan through the production width-1 loop.

      mix conveyor.run PLAN_ID [--adapter codex|reference_solution] [--workspace PATH] [--in-place]

  `PLAN_ID` is the UUID of a plan authored via the `conveyor.task.*` CLI (or brought in from a
  legacy YAML plan with `Conveyor.Planning.PlanImporter`). The run refuses unless every task is
  approved.

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
  def run([selector | args]) do
    Mix.Task.run("app.start")
    opts = parse_opts!(args)
    adapter = adapter!(Keyword.get(opts, :adapter, "codex"))
    workspace = resolve_workspace!(opts)

    case run_plan(selector, workspace, adapter, opts) do
      {:ok, result} ->
        disposition = disposition(result.serial_result)

        result
        |> summary(disposition)
        |> Map.put("workspace", workspace)
        |> Jason.encode!()
        |> Mix.shell().info()

        exit_fun().(exit_code(disposition))

      {:unapproved, message} ->
        # Human diagnostic on stderr; stdout stays pure JSON. The driver was never invoked.
        IO.puts(:stderr, message)
        exit_fun().(ExitCodes.fetch!(:plan_or_readiness_blocked))
    end
  end

  def run(_args), do: Mix.raise(usage())

  # The selector is a plan-id (YAML is retired, U7); legacy YAML plans are brought in once via
  # `Conveyor.Planning.PlanImporter`. The approval gate raises before the driver runs.
  defp run_plan(selector, workspace, adapter, opts) do
    unless uuid?(selector), do: Mix.raise(usage())

    result =
      PlanRunner.run_plan!(selector,
        workspace_path: workspace,
        blob_root: Keyword.get(opts, :blob_root),
        agent_adapter: adapter
      )

    {:ok, result}
  rescue
    error in [PlanRunner.UnapprovedError] -> {:unapproved, Exception.message(error)}
  end

  defp uuid?(string) do
    Regex.match?(
      ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i,
      string
    )
  end

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

  defp summary(result, disposition) do
    serial_result = result.serial_result
    report = serial_result.report

    %{
      "status" => Atom.to_string(serial_result.status),
      "disposition" => disposition,
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

  # dr1m.6.1/KTD-3: a :partial run advanced past ≥1 non-passing slice (M3
  # skip-and-continue). Split the old blanket :deterministic_gate_failed: a HARD
  # gate failure (a slice the gate REJECTED, or policy-blocked) stays
  # deterministic_gate_failed, while a run that only PARKED slices for human
  # review (trust abstained, reaped, rework-exhausted, or skipped behind a parked
  # predecessor) gets the distinct parked_for_review code — so an unattended
  # caller can tell "blocked on review" from "the gate said no".
  defp exit_code("passed"), do: ExitCodes.fetch!(:success)
  defp exit_code("gate_failed"), do: ExitCodes.fetch!(:deterministic_gate_failed)
  defp exit_code("parked_for_review"), do: ExitCodes.fetch!(:parked_for_review)

  defp disposition(%{status: :passed}), do: "passed"

  defp disposition(%{status: :partial, events: events}) do
    if hard_gate_failure?(events), do: "gate_failed", else: "parked_for_review"
  end

  # Defensive: SerialDriver.Result.status is :passed | :partial today. A future status
  # (or a :partial result somehow missing :events) must not crash the operator CLI with a
  # FunctionClauseError — treat the unknown as a non-zero gate failure rather than raise.
  defp disposition(_serial_result), do: "gate_failed"

  # A slice the gate hard-failed (critical → :rejected, or :policy_blocked). Every
  # other non-passing outcome (:abstained, :parked, :needs_rework, :skipped) is a
  # park awaiting a human, not a deterministic gate failure. run_attempt_outcome is
  # an atom in the in-memory event maps; to_string normalizes it (DB reads stringify).
  defp hard_gate_failure?(events) do
    Enum.any?(events, fn event ->
      to_string(Map.get(event, "run_attempt_outcome")) in ["rejected", "policy_blocked"]
    end)
  end

  defp usage do
    "usage: mix conveyor.run PLAN_ID [--adapter codex|reference_solution] [--workspace PATH] [--in-place]"
  end

  defp exit_fun do
    Process.get(:conveyor_run_exit_fun, &System.halt/1)
  end
end
