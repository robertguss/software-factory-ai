defmodule Conveyor.Planning.StructuralAudit do
  @moduledoc """
  Deterministic front-end structural audit for normalized planning contracts.

  This module is intentionally pure so planning interrogation can run it before
  any persistence or agent synthesis path.
  """

  @vague_terms [
    "better",
    "fast",
    "improve",
    "nice",
    "robust",
    "simple",
    "user-friendly",
    "tbd",
    "todo"
  ]

  defmodule Result do
    @moduledoc "Structural audit status and deterministic findings."

    @enforce_keys [:status, :findings]
    defstruct [:status, :findings]
  end

  @spec audit(map()) :: Result.t()
  def audit(contract) when is_map(contract) do
    normalized = normalize_keys(contract)

    findings =
      []
      |> Kernel.++(requirement_acceptance_findings(normalized))
      |> Kernel.++(planning_guardrail_findings(normalized))
      |> Kernel.++(acceptance_quality_findings(normalized))
      |> Kernel.++(contradiction_findings(normalized))
      |> Kernel.++(source_consistency_findings(normalized))
      |> Enum.sort_by(&{&1.rule_key, &1.subject_key, &1.message})

    %Result{status: status(findings), findings: findings}
  end

  defp requirement_acceptance_findings(contract) do
    requirements = list(contract, "requirements")
    acceptance_criteria = list(contract, "acceptance_criteria")
    requirement_keys = MapSet.new(requirements, &Map.get(&1, "key"))

    referenced_requirement_keys =
      acceptance_criteria
      |> Enum.flat_map(&string_list(&1, "requirement_refs"))
      |> MapSet.new()

    missing_acceptance =
      requirements
      |> Enum.reject(&(Map.get(&1, "key") in referenced_requirement_keys))
      |> Enum.map(fn requirement ->
        key = Map.fetch!(requirement, "key")

        finding(
          "missing_requirement_acceptance",
          key,
          "Requirement #{key} has no acceptance criterion.",
          [source_ref(requirement)],
          [],
          [%{kind: :edit_plan, target: key, label: "Add acceptance criteria for #{key}."}]
        )
      end)

    orphan_acceptance =
      acceptance_criteria
      |> Enum.filter(&(string_list(&1, "requirement_refs") == []))
      |> Enum.map(fn criterion ->
        key = Map.fetch!(criterion, "key")

        finding(
          "orphan_acceptance_criterion",
          key,
          "Acceptance criterion #{key} is not attached to a requirement.",
          [source_ref(criterion)],
          [],
          [%{kind: :edit_plan, target: key, label: "Attach #{key} to at least one requirement."}]
        )
      end)

    undefined_refs =
      acceptance_criteria
      |> Enum.flat_map(fn criterion ->
        key = Map.fetch!(criterion, "key")

        criterion
        |> string_list("requirement_refs")
        |> Enum.reject(&MapSet.member?(requirement_keys, &1))
        |> case do
          [] ->
            []

          refs ->
            [
              finding(
                "undefined_requirement_ref",
                key,
                "Acceptance criterion #{key} references undefined requirements.",
                [source_ref(criterion)],
                Enum.sort(refs),
                [
                  %{
                    kind: :edit_plan,
                    target: key,
                    label: "Define or remove undefined requirement refs for #{key}."
                  }
                ]
              )
            ]
        end
      end)

    missing_acceptance ++ orphan_acceptance ++ undefined_refs
  end

  defp planning_guardrail_findings(contract) do
    []
    |> maybe_add(
      string_items(contract, "non_goals") == [],
      finding(
        "missing_non_goals",
        "plan",
        "Plan records no non-goals.",
        [],
        [],
        [%{kind: :edit_plan, target: "non_goals", label: "Record explicit non-goals."}]
      )
    )
    |> maybe_add(
      list(contract, "decisions") == [],
      finding(
        "missing_decisions",
        "plan",
        "Plan records no architectural decisions.",
        [],
        [],
        [%{kind: :edit_plan, target: "decisions", label: "Record at least one DEC-* decision."}]
      )
    )
  end

  defp acceptance_quality_findings(contract) do
    contract
    |> list("acceptance_criteria")
    |> Enum.flat_map(fn criterion ->
      key = Map.fetch!(criterion, "key")

      []
      |> maybe_add(
        vague?(Map.get(criterion, "text", "")),
        finding(
          "unmeasurable_acceptance",
          key,
          "Acceptance criterion #{key} uses unmeasurable wording.",
          [source_ref(criterion)],
          [],
          [%{kind: :edit_plan, target: key, label: "Rewrite #{key} with measurable outcomes."}]
        )
      )
      |> maybe_add(
        oracle_refs(criterion) == [],
        finding(
          "missing_oracle_path",
          key,
          "Acceptance criterion #{key} has no oracle path.",
          [source_ref(criterion)],
          [],
          [
            %{
              kind: :edit_plan,
              target: key,
              label: "Add required tests or an oracle definition for #{key}."
            }
          ]
        )
      )
    end)
  end

  defp contradiction_findings(contract) do
    []
    |> Kernel.++(requirement_contradictions(list(contract, "requirements")))
    |> Kernel.++(
      definition_contradictions(
        list(contract, "enums"),
        "contradictory_enum",
        &values_signature/1
      )
    )
    |> Kernel.++(
      definition_contradictions(
        list(contract, "statuses"),
        "contradictory_status",
        &values_signature/1
      )
    )
    |> Kernel.++(interface_contradictions(list(contract, "interfaces")))
    |> Kernel.++(hard_constraint_contradictions(list(contract, "constraints")))
  end

  defp requirement_contradictions(requirements) do
    claims =
      requirements
      |> Enum.map(&polarized_statement/1)
      |> Enum.reject(&is_nil/1)

    for {positive_key, :positive, claim, positive_anchor} <- claims,
        {negative_key, :negative, ^claim, negative_anchor} <- claims,
        positive_key != negative_key do
      finding(
        "contradictory_requirement",
        positive_key,
        "Requirement #{positive_key} contradicts #{negative_key}.",
        Enum.reject([positive_anchor, negative_anchor], &is_nil/1),
        [negative_key],
        [
          %{
            kind: :human_decision,
            target: positive_key,
            label: "Resolve contradiction between #{positive_key} and #{negative_key}."
          }
        ]
      )
    end
  end

  defp definition_contradictions(items, rule_key, signature_fun) do
    items
    |> Enum.group_by(&Map.get(&1, "key"))
    |> Enum.flat_map(fn
      {nil, _items} ->
        []

      {key, grouped_items} ->
        signatures = grouped_items |> Enum.map(signature_fun) |> Enum.uniq()

        if length(signatures) > 1 do
          [
            finding(
              rule_key,
              key,
              "Definition #{key} has contradictory declarations.",
              Enum.map(grouped_items, &source_ref/1),
              Enum.map(signatures, &Enum.join(&1, ",")),
              [
                %{
                  kind: :human_decision,
                  target: key,
                  label: "Choose the authoritative declaration for #{key}."
                }
              ]
            )
          ]
        else
          []
        end
    end)
  end

  defp interface_contradictions(interfaces) do
    interfaces
    |> Enum.group_by(fn interface ->
      "#{Map.get(interface, "key")}@#{Map.get(interface, "version")}"
    end)
    |> Enum.flat_map(fn {subject_key, grouped_interfaces} ->
      schema_refs =
        grouped_interfaces
        |> Enum.map(&(Map.get(&1, "schema_ref") || Map.get(&1, "provider_schema_ref")))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()

      if length(schema_refs) > 1 do
        [
          finding(
            "contradictory_interface",
            subject_key,
            "Interface #{subject_key} has contradictory schema refs.",
            Enum.map(grouped_interfaces, &source_ref/1),
            schema_refs,
            [
              %{
                kind: :human_decision,
                target: subject_key,
                label: "Select the authoritative schema for #{subject_key}."
              }
            ]
          )
        ]
      else
        []
      end
    end)
  end

  defp hard_constraint_contradictions(constraints) do
    statements =
      constraints
      |> Enum.filter(&(Map.get(&1, "strength") == "hard"))
      |> Enum.map(&polarized_statement/1)
      |> Enum.reject(&is_nil/1)

    for {positive_key, :positive, statement, positive_anchor} <- statements,
        {negative_key, :negative, ^statement, negative_anchor} <- statements,
        positive_key != negative_key do
      finding(
        "contradictory_hard_constraint",
        positive_key,
        "Hard constraint #{positive_key} contradicts #{negative_key}.",
        Enum.reject([positive_anchor, negative_anchor], &is_nil/1),
        [negative_key],
        [
          %{
            kind: :human_decision,
            target: positive_key,
            label:
              "Resolve hard-constraint contradiction between #{positive_key} and #{negative_key}."
          }
        ]
      )
    end
  end

  defp source_consistency_findings(contract) do
    subjects =
      (list(contract, "requirements") ++
         list(contract, "acceptance_criteria") ++ list(contract, "decisions"))
      |> Map.new(&{Map.get(&1, "key"), &1})

    []
    |> Kernel.++(source_map_findings(list(contract, "source_map"), subjects))
    |> Kernel.++(claim_findings(list(contract, "claims"), subjects))
  end

  defp source_map_findings(source_map, subjects) do
    source_map
    |> Enum.flat_map(fn entry ->
      subject_ref = Map.get(entry, "subject_ref")
      declared_source = Map.get(entry, "source_ref")
      subject_source = subjects |> Map.get(subject_ref, %{}) |> Map.get("source_ref")

      if subject_ref && subject_source && declared_source != subject_source do
        [
          finding(
            "source_map_mismatch",
            subject_ref,
            "Source map for #{subject_ref} does not match the subject source.",
            Enum.reject([declared_source, subject_source], &is_nil/1),
            Enum.reject([declared_source, subject_source], &is_nil/1),
            [
              %{
                kind: :edit_plan,
                target: subject_ref,
                label: "Reconcile source map entry for #{subject_ref}."
              }
            ]
          )
        ]
      else
        []
      end
    end)
  end

  defp claim_findings(claims, subjects) do
    claims
    |> Enum.flat_map(fn claim ->
      subject_ref = Map.get(claim, "subject_ref")
      claim_text = Map.get(claim, "claim", "")
      subject_text = subjects |> Map.get(subject_ref, %{}) |> subject_text()

      if subject_ref && subject_text != "" && inconsistent_claim?(claim_text, subject_text) do
        [
          finding(
            "claim_subject_mismatch",
            subject_ref,
            "Claim for #{subject_ref} is inconsistent with the referenced subject.",
            [],
            [claim_text],
            [
              %{
                kind: :edit_plan,
                target: subject_ref,
                label: "Align claim text with #{subject_ref} or change the claim subject."
              }
            ]
          )
        ]
      else
        []
      end
    end)
  end

  defp finding(rule_key, subject_key, message, anchors, refs, next_actions) do
    %{
      severity: :blocking,
      rule_key: rule_key,
      subject_key: subject_key,
      message: message,
      anchors: Enum.reject(anchors, &is_nil/1),
      refs: refs,
      next_actions: next_actions
    }
  end

  defp status([]), do: :passed
  defp status(_findings), do: :blocked

  defp source_ref(map), do: Map.get(map, "source_ref")

  defp subject_text(nil), do: ""
  defp subject_text(subject), do: Map.get(subject, "text") || Map.get(subject, "decision") || ""

  defp values_signature(item) do
    item
    |> string_list("values")
    |> Enum.sort()
  end

  defp polarized_statement(item) do
    key = Map.get(item, "key")
    text = Map.get(item, "text") || Map.get(item, "statement")
    anchor = source_ref(item)
    normalized = normalize_statement(text)

    cond do
      is_nil(key) or normalized == "" ->
        nil

      String.contains?(normalized, "must not ") ->
        {key, :negative, String.replace(normalized, "must not ", "must "), anchor}

      String.contains?(normalized, "must ") ->
        {key, :positive, normalized, anchor}

      true ->
        nil
    end
  end

  defp inconsistent_claim?(claim_text, subject_text) do
    claim = normalize_statement(claim_text)
    subject = normalize_statement(subject_text)

    claim != "" and subject != "" and
      not String.contains?(subject, claim) and
      not String.contains?(claim, subject)
  end

  defp normalize_statement(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9 ]+/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp maybe_add(findings, true, finding), do: [finding | findings]
  defp maybe_add(findings, false, _finding), do: findings

  defp vague?(text) do
    normalized = text |> to_string() |> String.downcase()
    Enum.any?(@vague_terms, &String.contains?(normalized, &1))
  end

  defp oracle_refs(criterion) do
    string_list(criterion, "required_test_refs") ++
      string_list(criterion, "oracle_refs") ++
      string_list(criterion, "oracle_definition_refs")
  end

  defp list(map, key) do
    case Map.get(map, key) do
      values when is_list(values) -> Enum.filter(values, &is_map/1)
      _ -> []
    end
  end

  defp string_list(map, key) do
    case Map.get(map, key) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _ -> []
    end
  end

  defp string_items(map, key) do
    case Map.get(map, key) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _ -> []
    end
  end

  defp normalize_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_keys(value)} end)
  end

  defp normalize_keys(values) when is_list(values), do: Enum.map(values, &normalize_keys/1)
  defp normalize_keys(value), do: value
end
