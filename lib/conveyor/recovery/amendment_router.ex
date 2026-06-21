defmodule Conveyor.Recovery.AmendmentRouter do
  @moduledoc """
  ADR-26 — route a gate failure to the right recovery.

  Most gate failures mean the *code* is wrong (→ rework). Some mean the
  *contract* is wrong — an acceptance criterion that is impossible, contradictory,
  or unmeasurable — and no amount of code will satisfy it. This module classifies
  the failure and, on a contract defect, produces a **human-approval** plan-
  amendment proposal (via the existing, pure `Conveyor.Planning.PlanAmendments`)
  naming the implicated acceptance criteria.

  Separation of duties (ADR-07/13/19) is preserved: this is a conductor-side
  decision, the proposal is `human_review_required`, and the implementer never
  authors or relaxes its own contract.

  Conservative by construction: the default is `:code_defect` (rework); a contract
  defect requires an explicit structural finding (the `StructuralAudit` rule-keys).
  """

  alias Conveyor.Planning.PlanAmendments

  # Structural contract problems (StructuralAudit rule-keys). A finding carrying
  # one of these — surfaced at the gate or from a re-audit — means the contract,
  # not the diff, is the problem.
  @contract_defect_keys ~w(
    missing_requirement_acceptance
    orphan_acceptance_criterion
    undefined_requirement_ref
    unmeasurable_acceptance
    missing_oracle_path
    contradictory_requirement
    contradictory_acceptance
    contradictory_hard_constraint
    acceptance_unmappable
  )

  @type decision :: {:amend, map()} | :rework

  @doc "Classify a gate failure from its findings: `:contract_defect` or `:code_defect`."
  @spec classify([map()]) :: :contract_defect | :code_defect
  def classify(findings) when is_list(findings) do
    if Enum.any?(findings, &contract_defect_finding?/1), do: :contract_defect, else: :code_defect
  end

  @doc """
  Route a gate failure to a recovery decision.

  On a contract defect, returns `{:amend, proposal}` — a `human_review_required`
  plan-amendment proposal naming the implicated acceptance criteria. Otherwise
  `:rework` (the existing path). `opts` may carry `:plan_id`,
  `:base_plan_revision_id`, `:change_set_id`.
  """
  @spec route([map()], keyword()) :: decision()
  def route(findings, opts \\ []) when is_list(findings) and is_list(opts) do
    case classify(findings) do
      :contract_defect -> {:amend, PlanAmendments.propose(amendment_input(findings, opts))}
      :code_defect -> :rework
    end
  end

  defp amendment_input(findings, opts) do
    refs = implicated_acceptance_refs(findings)

    %{
      plan_id: Keyword.get(opts, :plan_id),
      base_plan_revision_id: Keyword.get(opts, :base_plan_revision_id),
      dispute_kind: "contract_defect",
      # acceptance is touched, so the proposal must be human-reviewed (never auto).
      materiality: "material",
      change_set_id: Keyword.get(opts, :change_set_id, "amendment:" <> Enum.join(refs, ",")),
      impact_confidence: 1.0,
      changed_subjects: Enum.map(refs, &%{subject_kind: "acceptance_criterion", subject_id: &1})
    }
  end

  defp implicated_acceptance_refs(findings) do
    findings
    |> Enum.filter(&contract_defect_finding?/1)
    |> Enum.map(&finding_ref/1)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
  end

  defp finding_ref(finding) do
    get(finding, "acceptance_criterion_id") || get(finding, "subject_key") ||
      get(finding, "anchor")
  end

  defp contract_defect_finding?(finding) do
    key = get(finding, "category") || get(finding, "rule_key")
    to_string(key) in @contract_defect_keys
  end

  defp get(finding, key) when is_map(finding) do
    Map.get(finding, key) || Map.get(finding, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(finding, key)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
