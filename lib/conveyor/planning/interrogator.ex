defmodule Conveyor.Planning.Interrogator do
  @moduledoc """
  Read-only plan interrogator.

  The interrogator asks humans to resolve deterministic front-end findings. It
  does not propose defaults or mutate planning state.
  """

  alias Conveyor.Planning.StructuralAudit

  defmodule Batch do
    @moduledoc "Deduplicated question batch produced from deterministic findings."

    @enforce_keys [
      :status,
      :role_view,
      :mutation_allowed?,
      :questions,
      :covered_finding_refs,
      :completeness
    ]
    defstruct [
      :status,
      :role_view,
      :mutation_allowed?,
      :questions,
      :covered_finding_refs,
      :completeness
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Question do
    @moduledoc "Ask-only human question linked to one or more deterministic findings."

    @enforce_keys [:id, :action, :prompt, :finding_refs, :anchors, :next_actions]
    defstruct [:id, :action, :prompt, :finding_refs, :anchors, :next_actions]
  end

  @spec question_batch(map(), keyword()) :: Batch.t()
  def question_batch(contract, opts \\ []) when is_map(contract) do
    audit = Keyword.get_lazy(opts, :audit, fn -> StructuralAudit.audit(contract) end)

    questions =
      audit.findings
      |> Enum.map(&question_for_finding/1)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)

    covered_finding_refs = questions |> Enum.flat_map(& &1.finding_refs) |> Enum.sort()

    %Batch{
      status: status(questions),
      role_view: %{scope: :plan_only, read_only?: true, allowed_actions: [:ask_human]},
      mutation_allowed?: false,
      questions: questions,
      covered_finding_refs: covered_finding_refs,
      completeness: completeness(audit.findings, covered_finding_refs, opts)
    }
  end

  defp question_for_finding(finding) do
    finding_ref = finding_ref(finding)

    %Question{
      id: "question:#{finding_ref}",
      action: :ask_human,
      prompt: prompt_for(finding),
      finding_refs: [finding_ref],
      anchors: finding.anchors,
      next_actions: finding.next_actions
    }
  end

  defp prompt_for(%{message: message, next_actions: [%{label: label} | _]}),
    do: "#{message} #{label}"

  defp prompt_for(%{message: message}), do: message

  defp finding_ref(finding), do: "#{finding.rule_key}:#{finding.subject_key}"

  defp completeness(findings, covered_finding_refs, opts) do
    expected_unsuppressed_refs =
      opts
      |> Keyword.get(:injection_fixtures, [])
      |> Enum.flat_map(&Map.get(&1, :expected_unsuppressed_refs, []))

    suppressed_finding_refs =
      expected_unsuppressed_refs
      |> Enum.reject(&(&1 in covered_finding_refs))
      |> Enum.sort()

    %{
      deterministic_finding_count: length(findings),
      covered_finding_count: length(covered_finding_refs),
      injection_fixture_count: length(Keyword.get(opts, :injection_fixtures, [])),
      suppressed_finding_refs: suppressed_finding_refs
    }
  end

  defp status([]), do: :complete
  defp status(_questions), do: :questions_required
end
