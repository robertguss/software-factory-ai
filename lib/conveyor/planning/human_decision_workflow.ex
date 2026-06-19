defmodule Conveyor.Planning.HumanDecisionWorkflow do
  @moduledoc """
  Applies one interrogation answer batch as explicit human decisions.

  The workflow is pure: it records draft checkpoints, publishes a new semantic
  revision only when answers change normalized semantics, and carries prior
  interrogations forward as evidence.
  """

  alias Conveyor.Planning.PlanningSpec
  alias Conveyor.Planning.RevisionLifecycle

  defmodule Result do
    @moduledoc "Outcome of applying a one-batch human decision workflow."

    @enforce_keys [:lifecycle, :human_decisions, :planning_spec, :prior_interrogation_refs]
    defstruct [:lifecycle, :human_decisions, :planning_spec, :prior_interrogation_refs]
  end

  @spec apply_answers(RevisionLifecycle.t(), struct(), [map()], keyword()) :: Result.t()
  def apply_answers(%RevisionLifecycle{} = lifecycle, batch, answers, opts)
      when is_list(answers) and is_list(opts) do
    interrogation_ref = Keyword.fetch!(opts, :interrogation_ref)
    draft_bytes = Keyword.fetch!(opts, :draft_bytes)
    normalized_contract = Keyword.fetch!(opts, :normalized_contract)

    lifecycle =
      RevisionLifecycle.save_draft_checkpoint!(lifecycle, draft_bytes, actor: actor!(answers))

    semantic_change? = Enum.any?(answers, &truthy?(Map.get(&1, :normalized_semantic_change?)))

    lifecycle =
      if semantic_change? do
        RevisionLifecycle.publish_revision!(lifecycle, normalized_contract,
          actor: actor!(answers)
        )
      else
        lifecycle
      end

    planning_spec = maybe_build_planning_spec(lifecycle, opts, semantic_change?)

    %Result{
      lifecycle: lifecycle,
      human_decisions: Enum.map(answers, &human_decision(&1, batch, interrogation_ref)),
      planning_spec: planning_spec,
      prior_interrogation_refs: [interrogation_ref]
    }
  end

  defp maybe_build_planning_spec(_lifecycle, _opts, false), do: nil

  defp maybe_build_planning_spec(lifecycle, opts, true) do
    revision = List.last(lifecycle.plan_revisions)

    opts
    |> Keyword.fetch!(:planning_spec_inputs)
    |> Map.put(:plan_revision_id, revision.revision_id)
    |> PlanningSpec.build!()
  end

  defp human_decision(answer, batch, interrogation_ref) do
    question_id = Map.fetch!(answer, :question_id)
    question = Enum.find(batch.questions, &(&1.id == question_id))

    %{
      question_id: question_id,
      actor: Map.fetch!(answer, :actor),
      decision_type: decision_type(answer),
      authority: :explicit_human,
      answer: Map.fetch!(answer, :answer),
      evidence_refs: [interrogation_ref],
      finding_refs: if(question, do: question.finding_refs, else: [])
    }
    |> drop_empty_finding_refs()
  end

  defp decision_type(answer) do
    if truthy?(Map.get(answer, :accepted_default?)), do: :accepted_default, else: :answer
  end

  defp drop_empty_finding_refs(%{finding_refs: []} = decision),
    do: Map.delete(decision, :finding_refs)

  defp drop_empty_finding_refs(decision), do: decision

  defp actor!([first | _]), do: Map.fetch!(first, :actor)
  defp actor!([]), do: raise(ArgumentError, "at least one human answer is required")

  defp truthy?(true), do: true
  defp truthy?(_), do: false
end
