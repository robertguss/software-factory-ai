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

  # rule_key => the plan-subject kind that rule implicates. Membership in this
  # table also *defines* "is this a contract defect?": every key is a real
  # `StructuralAudit` rule key, each meaning the contract (not the diff) is wrong.
  # Recording the right subject kind is the whole point — a `contradictory_requirement`
  # implicates a requirement, not an acceptance criterion, so the proposal must
  # not hard-label it `acceptance_criterion`. `AmendmentRouterTest` guards this
  # table against `StructuralAudit.rule_keys/0` so the two can never drift.
  @subject_kind_by_rule %{
    "missing_requirement_acceptance" => "requirement",
    "contradictory_requirement" => "requirement",
    "orphan_acceptance_criterion" => "acceptance_criterion",
    "undefined_requirement_ref" => "acceptance_criterion",
    "unmeasurable_acceptance" => "acceptance_criterion",
    "missing_oracle_path" => "acceptance_criterion",
    "contradictory_hard_constraint" => "hard_constraint",
    "contradictory_interface" => "interface",
    "contradictory_enum" => "enum",
    "contradictory_status" => "status",
    "missing_non_goals" => "plan",
    "missing_decisions" => "plan",
    "source_map_mismatch" => "plan_subject",
    "claim_subject_mismatch" => "plan_subject"
  }

  @type decision :: {:amend, map()} | :rework

  @doc "The rule_key => subject_kind table (also the set of contract-defect rule keys)."
  @spec subject_kinds() :: %{optional(String.t()) => String.t()}
  def subject_kinds, do: @subject_kind_by_rule

  @doc "Classify a gate failure from its findings: `:contract_defect` or `:code_defect`."
  @spec classify([map()]) :: :contract_defect | :code_defect
  def classify(findings) when is_list(findings) do
    if Enum.any?(findings, &contract_defect_finding?/1), do: :contract_defect, else: :code_defect
  end

  @doc """
  Route a gate failure to a recovery decision.

  On a contract defect, returns `{:amend, proposal}` — a `human_review_required`
  plan-amendment proposal naming each implicated subject with its correct kind.
  Otherwise `:rework` (the existing path). `opts` may carry `:plan_id`,
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
    subjects = implicated_subjects(findings)
    ids = Enum.map(subjects, & &1.subject_id)

    %{
      plan_id: Keyword.get(opts, :plan_id),
      base_plan_revision_id: Keyword.get(opts, :base_plan_revision_id),
      dispute_kind: "contract_defect",
      # the contract is being changed, so the proposal must be human-reviewed.
      materiality: "material",
      change_set_id: Keyword.get(opts, :change_set_id, "amendment:" <> Enum.join(ids, ",")),
      impact_confidence: 1.0,
      changed_subjects: subjects
    }
  end

  # One `%{subject_kind, subject_id}` per contract-defect finding, each carrying
  # the kind the rule actually implicates. De-duplicated (one subject can trip two
  # rules) and order-stable.
  defp implicated_subjects(findings) do
    findings
    |> Enum.filter(&contract_defect_finding?/1)
    |> Enum.map(fn finding ->
      %{
        subject_kind: Map.fetch!(@subject_kind_by_rule, finding_rule_key(finding)),
        subject_id: finding_subject(finding)
      }
    end)
    |> Enum.reject(&blank?(&1.subject_id))
    |> Enum.uniq()
  end

  defp contract_defect_finding?(finding) do
    Map.has_key?(@subject_kind_by_rule, finding_rule_key(finding))
  end

  # Real `StructuralAudit` findings carry an atom `:rule_key`; gate findings carry
  # a string `"category"`. Read whichever is present.
  defp finding_rule_key(finding) do
    to_string(get(finding, "rule_key") || get(finding, "category") || "")
  end

  # `StructuralAudit` names the implicated subject in `:subject_key`; tolerate a
  # couple of legacy gate-finding aliases.
  defp finding_subject(finding) do
    get(finding, "subject_key") || get(finding, "acceptance_criterion_id") ||
      get(finding, "subject_id") || get(finding, "anchor")
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
