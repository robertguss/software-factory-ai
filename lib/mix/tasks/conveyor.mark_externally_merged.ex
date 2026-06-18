defmodule Mix.Tasks.Conveyor.MarkExternallyMerged do
  @moduledoc """
  Records the human integration decision for a run attempt.

      mix conveyor.mark_externally_merged RUN_ATTEMPT_ID --external-commit SHA --actor ACTOR
      mix conveyor.mark_externally_merged RUN_ATTEMPT_ID --not-integrated --actor ACTOR
  """

  use Mix.Task

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.HumanIntegration

  @shortdoc "Record a manual external integration decision"

  @impl Mix.Task
  def run([run_attempt_id | args]) do
    Mix.Task.run("app.start")

    opts = parse_opts!(args)

    approval =
      opts
      |> Keyword.put(:run_attempt_id, run_attempt_id)
      |> HumanIntegration.record!()

    approval
    |> approval_json()
    |> Jason.encode!()
    |> Mix.shell().info()

    exit_fun().(ExitCodes.fetch!(:success))
  end

  def run(_args) do
    Mix.raise(usage())
  end

  defp parse_opts!(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          actor: :string,
          external_commit: :string,
          not_integrated: :boolean,
          rationale: :string
        ]
      )

    if remaining != [] or invalid != [] do
      Mix.raise(usage())
    end

    opts
    |> require_actor!()
    |> normalize_keys()
  end

  defp require_actor!(opts) do
    if opts[:actor] in [nil, ""] do
      Mix.raise(usage())
    end

    opts
  end

  defp normalize_keys(opts) do
    opts
    |> maybe_put(:external_commit, opts[:external_commit])
    |> maybe_put(:not_integrated, opts[:not_integrated])
    |> maybe_put(:rationale, opts[:rationale])
    |> Keyword.put(:actor, opts[:actor])
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp approval_json(approval) do
    %{
      "id" => approval.id,
      "project_id" => approval.project_id,
      "slice_id" => approval.slice_id,
      "run_attempt_id" => approval.run_attempt_id,
      "approval_type" => approval.approval_type,
      "decision" => Atom.to_string(approval.decision),
      "actor" => approval.actor,
      "rationale" => approval.rationale,
      "external_commit" => approval.external_commit,
      "equivalence_decision" => atom_string(approval.equivalence_decision)
    }
  end

  defp atom_string(nil), do: nil
  defp atom_string(value), do: Atom.to_string(value)

  defp usage do
    """
    usage:
      mix conveyor.mark_externally_merged RUN_ATTEMPT_ID --external-commit SHA --actor ACTOR [--rationale TEXT]
      mix conveyor.mark_externally_merged RUN_ATTEMPT_ID --not-integrated --actor ACTOR [--rationale TEXT]
    """
    |> String.trim()
  end

  defp exit_fun do
    Process.get(:conveyor_mark_externally_merged_exit_fun, &System.halt/1)
  end
end
