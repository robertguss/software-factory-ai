defmodule Mix.Tasks.Conveyor.Author do
  @moduledoc """
  Draft a `conveyor.plan@1` from a paragraph of intent (ADR-27 Plan Foundry / M5).

      mix conveyor.author "INTENT" [--out PATH] [--import [--workspace-path DIR]]

  Drives `Conveyor.Planning.PlanFoundry.draft/2` (the deterministic spine: an injectable
  Drafter -> StructuralAudit -> interrogation). Writes the drafted plan to `--out`
  (default `conveyor.plan.json`) and prints a JSON summary when the draft is structurally
  clean; prints the operator questions and exits non-zero when the audit needs
  clarification. The draft is not yet a runnable plan (decomposition is the next M5
  slice), so this does not hand off to `mix conveyor.run`.
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.PlanContract
  alias Conveyor.Planning.Author
  alias Conveyor.Planning.PlanImporter

  @shortdoc "Draft a Conveyor plan from a statement of intent"

  @impl Mix.Task
  def run(args) do
    {opts, positional} = parse_opts!(args)
    Mix.Task.run("app.start")
    intent = Enum.join(positional, " ")

    case Author.author(intent,
           out: Keyword.get(opts, :out, "conveyor.plan.json"),
           draft_opts: draft_opts()
         ) do
      {:ok, %{plan: plan, path: path}} ->
        if opts[:import] do
          import_draft(path, opts)
        else
          emit(%{
            "status" => "drafted",
            "out" => path,
            "requirement_count" => length(Map.get(plan, "requirements", [])),
            "acceptance_criteria_count" => length(Map.get(plan, "acceptance_criteria", []))
          })

          exit_fun().(ExitCodes.fetch!(:success))
        end

      {:needs_clarification, questions} ->
        emit(%{
          "status" => "needs_clarification",
          "questions" => Enum.map(questions, &%{"id" => &1.id, "prompt" => &1.prompt})
        })

        exit_fun().(ExitCodes.fetch!(:deterministic_gate_failed))

      {:error, :empty_intent} ->
        Mix.raise(usage())

      {:error, reason} ->
        Mix.raise("plan authoring failed: #{inspect(reason)}")
    end
  end

  # aaun.2: when the audited draft is schema-valid AND decomposed, hand it straight to the DB
  # via the SAME code path as `mix conveyor.plan.import` (PlanContract.load + PlanImporter),
  # then print the created IDs and the follow-up approve command. --import is impossible when
  # the draft is not runnable (no slices) — it refuses rather than writing a half-plan.
  defp import_draft(path, opts) do
    case PlanContract.load(path) do
      {:ok, result} ->
        if decomposed?(result.contract) do
          imported = PlanImporter.import_result!(result, import_opts(opts))

          emit(%{
            "status" => "imported",
            "out" => path,
            "project_id" => imported.project.id,
            "plan_id" => imported.plan.id,
            "epic_id" => imported.epic.id,
            "slice_count" => map_size(imported.slices_by_stable_key),
            "next" => "mix conveyor.plan.approve #{imported.plan.id}"
          })

          exit_fun().(ExitCodes.fetch!(:success))
        else
          emit(%{
            "status" => "not_decomposed",
            "out" => path,
            "error" =>
              "draft has no slices — run the decomposer or hand-finish the JSON before --import"
          })

          exit_fun().(ExitCodes.fetch!(:plan_or_readiness_blocked))
        end

      {:error, %PlanContract.Error{} = error} ->
        emit(%{"status" => "import_failed", "out" => path, "error" => error.message})
        exit_fun().(ExitCodes.fetch!(:malformed_artifact_or_schema_failure))
    end
  end

  defp decomposed?(contract) do
    case Map.get(contract, "slices") do
      [_ | _] -> true
      _ -> false
    end
  end

  defp import_opts(opts) do
    case opts[:workspace_path] do
      nil -> []
      path -> [workspace_path: path]
    end
  end

  defp parse_opts!(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args, strict: [out: :string, import: :boolean, workspace_path: :string])

    if invalid != [], do: Mix.raise(usage())
    {opts, positional}
  end

  defp emit(map), do: Mix.shell().info(Jason.encode!(map))

  # Injected by tests (mirrors `mix conveyor.run`): the Drafter override + the exit
  # function, so the task is driven deterministically without a live agent or a halt.
  defp draft_opts, do: Process.get(:conveyor_author_draft_opts, [])
  defp exit_fun, do: Process.get(:conveyor_author_exit_fun, &System.halt/1)

  defp usage, do: ~s(usage: mix conveyor.author "INTENT" [--out PATH])
end
