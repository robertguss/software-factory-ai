defmodule Conveyor.Planning.MaterialityPolicy do
  @moduledoc """
  Deterministic materiality classifier and micro-negotiation policy.

  The reducer separates classification from authority. Shadow mode may record a
  narrow would-accept decision, but only pre-attempt auto-accept can produce an
  actual auto-accept, and then only under the full eligibility checklist.
  """

  @material_labels ~w(
    acceptance_weakened
    obligation_changed
    decision_changed
    hard_constraint_changed
    scope_added
    scope_removed
    scope_reinterpreted
    compatibility_weakened
    waiver_weakened
    policy_weakened
    risk_increased
    public_compatibility_weakened
    grant_changing
    contract_changing
    evidence_changing
    environment_changing
    capability_changing
    approval_changing
    incomparable
  )

  @authority_areas ~w(
    acceptance_criteria
    obligation
    decision
    hard_constraint
    scope
    policy
    risk
    waiver
    public_compatibility
  )

  @public_compatibility_areas ~w(public_compatibility)
  @narrow_auto_labels ~w(compatibility_superset example_added type_clarification)
  @narrow_auto_areas ~w(compatibility example type)

  @spec adjudicate(map()) :: map()
  def adjudicate(input) when is_map(input) do
    labels = strings(input, :materiality_labels)
    touched_areas = strings(input, :touched_areas)
    materiality = classify(labels, touched_areas)
    reasons = reason_codes(input, labels, touched_areas, materiality)
    narrow_auto? = narrow_auto_eligible?(input, labels, touched_areas, materiality)
    mode = value(input, :mode, "human_gated")

    base = %{
      "mode" => mode,
      "materiality" => materiality,
      "reason_codes" => reasons,
      "auto_accept" => false,
      "creates_new_authority_chain" => false
    }

    case mode do
      "shadow_adjudication" ->
        base
        |> Map.put("authority_decision", "require_human")
        |> Map.put(
          "shadow_decision",
          if(narrow_auto?, do: "would_auto_accept", else: "would_require_human")
        )

      "pre_attempt_auto_accept" ->
        if narrow_auto? do
          base
          |> Map.put("authority_decision", "auto_accept")
          |> Map.put("auto_accept", true)
          |> Map.put("creates_new_authority_chain", true)
        else
          Map.put(base, "authority_decision", "require_human")
        end

      _other ->
        Map.put(base, "authority_decision", "require_human")
    end
  end

  defp classify(labels, touched_areas) do
    cond do
      Enum.any?(labels, &(&1 in @material_labels)) -> "material"
      Enum.any?(touched_areas, &(&1 in @authority_areas)) -> "material"
      Enum.any?(labels, &(&1 in @narrow_auto_labels)) -> "nonmaterial"
      labels == [] and touched_areas == [] -> "clarification"
      true -> "nonmaterial"
    end
  end

  defp reason_codes(input, labels, touched_areas, materiality) do
    []
    |> maybe(materiality == "material", "authority_meaning_changed")
    |> maybe(
      value(input, :originating_role) == "implementer" and
        value(input, :requested_materiality) in ["clarification", "nonmaterial"],
      "implementer_self_declaration_ignored"
    )
    |> maybe(
      Enum.any?(touched_areas, &(&1 in @public_compatibility_areas)),
      "public_compatibility_touched"
    )
    |> maybe(not narrow_label_set?(labels), "outside_narrow_auto_policy")
    |> Enum.reverse()
  end

  defp narrow_auto_eligible?(input, labels, touched_areas, "nonmaterial") do
    narrow_label_set?(labels) and
      narrow_area_set?(touched_areas) and
      value(input, :preserves_existing_consumers) == true and
      value(input, :contract_author_verdict) == "accepted" and
      value(input, :before_attempt_started) == true and
      value(input, :active_qualification_grant) == true and
      within_round_limit?(input)
  end

  defp narrow_auto_eligible?(_input, _labels, _touched_areas, _materiality), do: false

  defp narrow_label_set?(labels),
    do: labels != [] and Enum.all?(labels, &(&1 in @narrow_auto_labels))

  defp narrow_area_set?(areas), do: Enum.all?(areas, &(&1 in @narrow_auto_areas))

  defp within_round_limit?(input) do
    round = value(input, :negotiation_round, 1)
    limit = value(input, :negotiation_round_limit, 1)

    is_integer(round) and is_integer(limit) and round <= limit
  end

  defp maybe(reasons, true, reason), do: [reason | reasons]
  defp maybe(reasons, false, _reason), do: reasons

  defp strings(map, key) do
    map
    |> value(key, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))
end
