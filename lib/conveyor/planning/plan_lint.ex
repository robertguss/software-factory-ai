defmodule Conveyor.Planning.PlanLint do
  @moduledoc """
  Deterministic, non-authorizing plan lint for static compiler products.
  """

  alias Conveyor.Planning.StructuralAudit

  @allowed_suppression_types ["human_decision", "policy_waiver"]
  @blocking_decision_statuses ["blocked", "open", "pending", "unresolved"]

  @spec lint(map()) :: map()
  def lint(contract) when is_map(contract) do
    normalized = normalize_keys(contract)

    findings =
      normalized
      |> canonical_findings()
      |> apply_suppressions(list(normalized, "suppressions"))
      |> Enum.sort_by(&{&1.rule_key, &1.subject_key, &1.message})
      |> Enum.map(&with_finding_id/1)

    %{
      schema_version: "conveyor.plan_lint@1",
      status: if(findings == [], do: :passed, else: :blocked),
      authority_effect: :none,
      creates_contract_lock?: false,
      creates_approval?: false,
      creates_ready_slice?: false,
      implementer_launched?: false,
      findings: findings,
      finding_ids: Enum.map(findings, & &1.finding_id)
    }
  end

  @spec render(map(), keyword()) :: map() | String.t()
  def render(result, opts \\ []) when is_map(result) do
    case Keyword.get(opts, :format, :human) do
      :human -> human(result)
      :json -> result
      :sarif -> sarif(result)
    end
  end

  @spec prepare(map()) :: map()
  def prepare(contract) when is_map(contract) do
    lint = lint(contract)

    %{
      schema_version: "conveyor.plan_prepare@1",
      status: lint.status,
      no_agents: true,
      agent_runner_used: false,
      provider_credentials_required: false,
      authority_effect: :none,
      creates_contract_lock?: false,
      creates_approval?: false,
      creates_ready_slice?: false,
      implementer_launched?: false,
      lint: lint
    }
  end

  defp canonical_findings(contract) do
    contract
    |> StructuralAudit.audit()
    |> Map.fetch!(:findings)
    |> Enum.map(&normalize_structural_finding/1)
    |> Kernel.++(hard_constraint_findings(contract))
    |> Kernel.++(ambiguous_interface_findings(contract))
    |> Kernel.++(human_decision_findings(contract))
    |> Kernel.++(weak_oracle_findings(contract))
    |> Kernel.++(critical_context_findings(contract))
  end

  defp hard_constraint_findings(contract) do
    has_hard_constraint? =
      contract
      |> list("constraints")
      |> Enum.any?(&(Map.get(&1, "strength") in ["hard", :hard]))

    if has_hard_constraint? do
      []
    else
      [
        finding(
          "missing_hard_constraint",
          "plan",
          "Plan records no hard constraints.",
          [],
          [],
          [%{kind: :edit_plan, target: "constraints", label: "Add explicit hard constraints."}]
        )
      ]
    end
  end

  defp ambiguous_interface_findings(contract) do
    contract
    |> list("interfaces")
    |> Enum.filter(fn interface ->
      present?(Map.get(interface, "required_by")) and
        blank?(Map.get(interface, "schema_ref")) and
        blank?(Map.get(interface, "provider_schema_ref")) and
        blank?(Map.get(interface, "owner_slice_key"))
    end)
    |> Enum.map(fn interface ->
      key = Map.get(interface, "key", "unknown")

      finding(
        "ambiguous_interface",
        key,
        "Interface #{key} is required but has no schema or provider owner.",
        [Map.get(interface, "source_ref")],
        [],
        [%{kind: :edit_plan, target: key, label: "Bind #{key} to a schema and provider."}]
      )
    end)
  end

  defp human_decision_findings(contract) do
    (list(contract, "decisions") ++ list(contract, "human_decisions"))
    |> Enum.filter(&(Map.get(&1, "status") in @blocking_decision_statuses))
    |> Enum.map(fn decision ->
      key = Map.get(decision, "key") || Map.get(decision, "human_decision_ref") || "unknown"

      finding(
        "human_decision_blocker",
        key,
        "Human decision #{key} is unresolved.",
        [Map.get(decision, "source_ref")],
        [],
        [%{kind: :human_decision, target: key, label: "Resolve #{key} before lint passes."}]
      )
    end)
  end

  defp weak_oracle_findings(contract) do
    contract
    |> list("acceptance_criteria")
    |> Enum.filter(&weak_oracle?/1)
    |> Enum.map(fn criterion ->
      key = Map.get(criterion, "key", "unknown")

      finding(
        "weak_oracle_path",
        key,
        "Acceptance criterion #{key} relies on a weak oracle path.",
        [Map.get(criterion, "source_ref")],
        oracle_refs(criterion),
        [%{kind: :edit_plan, target: key, label: "Replace weak oracle refs for #{key}."}]
      )
    end)
  end

  defp critical_context_findings(contract) do
    budget =
      case Map.get(contract, "context_budget") || Map.get(contract, "critical_context_budget") do
        budget when is_map(budget) -> budget
        _other -> %{}
      end

    required =
      Map.get(budget, "critical_required_tokens") ||
        Map.get(budget, "required_tokens") ||
        Map.get(budget, "critical_tokens")

    max = Map.get(budget, "max_tokens") || Map.get(budget, "budget_tokens")

    if is_number(required) and is_number(max) and required > max do
      [
        finding(
          "critical_context_budget_impossible",
          "context",
          "Critical context requires more tokens than the available budget.",
          [],
          ["#{required}>#{max}"],
          [
            %{
              kind: :edit_plan,
              target: "context_budget",
              label: "Reduce critical context or raise the static budget."
            }
          ]
        )
      ]
    else
      []
    end
  end

  defp apply_suppressions(findings, suppressions) do
    {allowed, ignored} = Enum.split_with(suppressions, &typed_suppression?/1)

    unsuppressed =
      Enum.reject(findings, fn finding ->
        Enum.any?(allowed, &suppression_matches?(&1, finding))
      end)

    ignored_findings =
      ignored
      |> Enum.filter(fn suppression ->
        Enum.any?(findings, &suppression_matches?(suppression, &1))
      end)
      |> Enum.map(fn suppression ->
        subject = "#{Map.get(suppression, "rule_key")}:#{Map.get(suppression, "subject_key")}"

        finding(
          "suppression_ignored",
          subject,
          "Suppression #{subject} is not backed by a typed HumanDecision or policy waiver.",
          [Map.get(suppression, "source_ref")],
          [],
          [
            %{
              kind: :human_decision,
              target: subject,
              label: "Replace untyped suppression with HumanDecision or policy waiver."
            }
          ]
        )
      end)

    unsuppressed ++ ignored_findings
  end

  defp typed_suppression?(suppression) do
    Map.get(suppression, "type") in @allowed_suppression_types or
      Map.get(suppression, "kind") in @allowed_suppression_types
  end

  defp suppression_matches?(suppression, finding) do
    Map.get(suppression, "rule_key") == finding.rule_key and
      Map.get(suppression, "subject_key") == finding.subject_key
  end

  defp weak_oracle?(criterion) do
    Map.get(criterion, "oracle_strength") in ["weak", :weak] or
      Enum.any?(oracle_refs(criterion), fn ref ->
        ref
        |> to_string()
        |> String.downcase()
        |> then(&(String.contains?(&1, "manual") or String.contains?(&1, "human")))
      end)
  end

  defp oracle_refs(criterion) do
    string_list(criterion, "oracle_refs") ++
      string_list(criterion, "oracle_definition_refs") ++
      string_list(criterion, "required_test_refs")
  end

  defp normalize_structural_finding(finding) do
    finding(
      Map.fetch!(finding, :rule_key),
      Map.fetch!(finding, :subject_key),
      Map.fetch!(finding, :message),
      Map.get(finding, :anchors, []),
      Map.get(finding, :refs, []),
      Map.get(finding, :next_actions, [])
    )
  end

  defp finding(rule_key, subject_key, message, anchors, refs, next_actions) do
    %{
      severity: :blocking,
      rule_key: rule_key,
      subject_key: subject_key,
      message: message,
      source_anchors: Enum.reject(anchors, &blank?/1),
      refs: refs,
      next_actions: next_actions
    }
  end

  defp with_finding_id(finding) do
    Map.put(finding, :finding_id, "#{finding.rule_key}:#{finding.subject_key}")
  end

  defp human(result) do
    header = [
      "plan_lint: #{result.status}",
      "Mode: NON-authorizing",
      "Authority: #{result.authority_effect}"
    ]

    findings =
      case result.findings do
        [] ->
          ["Findings: none"]

        findings ->
          [
            "Findings:"
            | Enum.map(findings, fn finding ->
                "- #{finding.rule_key}: #{finding.subject_key} #{finding.message}"
              end)
          ]
      end

    Enum.join(header ++ findings, "\n")
  end

  defp sarif(result) do
    rules =
      result.findings
      |> Enum.uniq_by(& &1.rule_key)
      |> Enum.map(fn finding ->
        %{
          id: finding.rule_key,
          name: finding.rule_key,
          shortDescription: %{text: finding.message}
        }
      end)

    %{
      version: "2.1.0",
      "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
      runs: [
        %{
          tool: %{driver: %{name: "conveyor.plan_lint", rules: rules}},
          results: Enum.map(result.findings, &sarif_result/1)
        }
      ]
    }
  end

  defp sarif_result(finding) do
    %{
      ruleId: finding.rule_key,
      level: "error",
      message: %{text: finding.message},
      locations: Enum.map(finding.source_anchors, &sarif_location/1),
      properties: %{
        finding_id: finding.finding_id,
        subject_key: finding.subject_key,
        source_anchors: finding.source_anchors,
        refs: finding.refs
      }
    }
  end

  defp sarif_location(anchor) do
    {uri, fragment} =
      case String.split(anchor, "#", parts: 2) do
        [uri, fragment] -> {uri, fragment}
        [uri] -> {uri, nil}
      end

    %{
      physicalLocation: %{
        artifactLocation:
          %{uri: uri}
          |> maybe_put(:uriBaseId, fragment)
      }
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

  defp normalize_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_keys(value)} end)
  end

  defp normalize_keys(values) when is_list(values), do: Enum.map(values, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp blank?(value), do: value in [nil, "", []]
  defp present?(value), do: not blank?(value)
end
