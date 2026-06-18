defmodule Conveyor.Gate.Stages.ObservedRisk do
  @moduledoc """
  Gate stage 3: classifies observed patch risk and applies escalation policy.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Factory
  alias Conveyor.Factory.RiskAssessment
  alias Conveyor.Gate.StageResult

  @risk_order %{"low" => 0, "medium" => 1, "high" => 2, "critical" => 3}
  @review_kinds [:general, :security, :test, :architecture]

  @impl true
  def run(context, _opts \\ []) do
    patch_set = value(context, :patch_set)
    review_policy = value(context, :review_policy)

    with :ok <- require_present(patch_set, "missing_patch_set", "PatchSet is required."),
         :ok <-
           require_present(review_policy, "missing_review_policy", "ReviewPolicy is required.") do
      planned_risk = normalize_risk(value(context, :planned_risk) || "low")
      classification = classify(patch_set, review_policy, planned_risk)
      maybe_persist_assessment(context, patch_set, classification)
      findings = findings(classification, review_policy, context)

      %StageResult{
        key: "observed_risk",
        status: status(findings),
        required?: true,
        findings: findings,
        evidence_refs: evidence_refs(patch_set),
        input_digests: %{
          "patch_sha256" => value(patch_set, :patch_sha256),
          "planned_risk" => classification.planned_risk,
          "observed_risk" => classification.observed_risk
        },
        output_digest: digest(classification)
      }
    else
      {:error, finding} ->
        %StageResult{
          key: "observed_risk",
          status: :failed,
          required?: true,
          findings: [finding],
          evidence_refs: evidence_refs(patch_set)
        }
    end
  end

  defp classify(patch_set, review_policy, planned_risk) do
    facts = facts(patch_set)

    matching_rules =
      Enum.filter(value(review_policy, :risk_rules) || [], &rule_matches?(&1, facts))

    default_review_kinds =
      normalize_review_kinds(value(review_policy, :default_required_review_kinds))

    observed_risk =
      matching_rules
      |> Enum.map(&normalize_risk(get(&1, :observed_risk)))
      |> Enum.reduce("low", &max_risk/2)

    required_review_kinds =
      matching_rules
      |> Enum.flat_map(&normalize_review_kinds(get(&1, :required_review_kinds)))
      |> then(&(default_review_kinds ++ &1))
      |> Enum.uniq()

    %{
      planned_risk: planned_risk,
      observed_risk: observed_risk,
      observed_exceeds_planned?: exceeds?(observed_risk, planned_risk),
      reasons: reasons(matching_rules, facts),
      touched_risk_domains: facts.domains,
      required_review_kinds: required_review_kinds,
      required_gate_stages: required_gate_stages(matching_rules),
      require_human_approval?: require_human_approval?(matching_rules)
    }
  end

  defp facts(patch_set) do
    files = value(patch_set, :changed_files) || []
    lines_added = value(patch_set, :lines_added) || 0
    lines_deleted = value(patch_set, :lines_deleted) || 0

    booleans = %{
      "dependency_changes" => Enum.any?(files, &dependency_path?/1),
      "migration_changes" => Enum.any?(files, &migration_path?/1),
      "generated_file_changes" => Enum.any?(files, &generated_path?/1),
      "public_api_changes" => Enum.any?(files, &public_api_path?/1),
      "locked_path_touched" => value(patch_set, :touches_locked_paths) == true
    }

    %{
      files: files,
      lines_added: lines_added,
      lines_deleted: lines_deleted,
      file_count: length(files),
      booleans: booleans,
      domains: touched_domains(booleans)
    }
  end

  defp rule_matches?(rule, facts) do
    conditions = get(rule, :when) || %{}

    Enum.all?(conditions, fn {key, expected} ->
      condition_matches?(to_string(key), expected, facts)
    end)
  end

  defp condition_matches?(key, globs, facts)
       when key in ["path_globs", "changed_path_globs"] and is_list(globs) do
    Enum.any?(facts.files, &matches_any?(&1, globs))
  end

  defp condition_matches?(key, expected, facts)
       when key in [
              "dependency_changes",
              "dependency_change",
              "migration_changes",
              "migration_change",
              "generated_file_changes",
              "generated_file_change",
              "public_api_changes",
              "public_api_change",
              "locked_path_touched"
            ] do
    canonical = plural_change_key(key)
    Map.get(facts.booleans, canonical) == expected
  end

  defp condition_matches?("touched_risk_domains", expected, facts) when is_list(expected) do
    expected = Enum.map(expected, &to_string/1)
    Enum.any?(expected, &(&1 in facts.domains))
  end

  defp condition_matches?("min_lines_added", expected, facts) when is_integer(expected),
    do: facts.lines_added >= expected

  defp condition_matches?("min_lines_deleted", expected, facts) when is_integer(expected),
    do: facts.lines_deleted >= expected

  defp condition_matches?("min_files_changed", expected, facts) when is_integer(expected),
    do: facts.file_count >= expected

  defp condition_matches?(_key, _expected, _facts), do: false

  defp reasons([], facts) do
    if facts.domains == [],
      do: ["no risk rules matched"],
      else: Enum.map(facts.domains, &"touched #{&1}")
  end

  defp reasons(matching_rules, _facts) do
    matching_rules
    |> Enum.map(&(get(&1, :reason) || get(&1, :message) || default_rule_reason(&1)))
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp required_gate_stages(matching_rules) do
    matching_rules
    |> Enum.flat_map(fn rule -> List.wrap(get(rule, :required_gate_stages)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp require_human_approval?(matching_rules) do
    Enum.any?(matching_rules, &(get(&1, :require_human_approval) == true))
  end

  defp findings(classification, review_policy, context) do
    escalation_policy = value(review_policy, :escalation_policy) || :fail_closed
    human_approval_granted? = value(context, :human_approval_granted) == true

    []
    |> maybe_add_observed_exceeds_planned(
      classification,
      escalation_policy,
      human_approval_granted?
    )
    |> maybe_add_human_approval(classification, escalation_policy, human_approval_granted?)
  end

  defp maybe_add_observed_exceeds_planned(
         findings,
         %{observed_exceeds_planned?: false},
         _policy,
         _human_approval_granted?
       ),
       do: findings

  defp maybe_add_observed_exceeds_planned(
         findings,
         classification,
         :allow_with_warning,
         _human_approval_granted?
       ) do
    [
      finding(
        "observed_risk_exceeds_planned",
        "warning",
        classification,
        "Observed risk exceeds planned risk."
      )
      | findings
    ]
  end

  defp maybe_add_observed_exceeds_planned(findings, classification, :require_human, true) do
    [
      finding(
        "observed_risk_exceeds_planned",
        "warning",
        classification,
        "Observed risk exceeds planned risk and was escalated to human approval."
      )
      | findings
    ]
  end

  defp maybe_add_observed_exceeds_planned(
         findings,
         classification,
         policy,
         _human_approval_granted?
       ) do
    message =
      case policy do
        :require_human -> "Observed risk exceeds planned risk and requires human approval."
        _policy -> "Observed risk exceeds planned risk; failing closed."
      end

    [finding("observed_risk_exceeds_planned", "blocking", classification, message) | findings]
  end

  defp maybe_add_human_approval(findings, %{require_human_approval?: false}, _policy, _granted?),
    do: findings

  defp maybe_add_human_approval(findings, _classification, _policy, true), do: findings

  defp maybe_add_human_approval(findings, classification, _policy, false) do
    [
      finding(
        "human_approval_required",
        "blocking",
        classification,
        "ReviewPolicy risk rule requires human approval."
      )
      | findings
    ]
  end

  defp finding(category, severity, classification, message) do
    %{
      "category" => category,
      "severity" => severity,
      "message" => message,
      "planned_risk" => classification.planned_risk,
      "observed_risk" => classification.observed_risk,
      "required_review_kinds" =>
        Enum.map(classification.required_review_kinds, &Atom.to_string/1),
      "required_gate_stages" => classification.required_gate_stages,
      "require_human_approval" => classification.require_human_approval?,
      "reasons" => classification.reasons,
      "touched_risk_domains" => classification.touched_risk_domains
    }
  end

  defp status(findings) do
    if Enum.any?(findings, &(&1["severity"] == "blocking")), do: :failed, else: :passed
  end

  defp maybe_persist_assessment(context, patch_set, classification) do
    run_attempt_id = value(context, :run_attempt_id) || value(value(context, :run_attempt), :id)
    patch_set_id = value(context, :patch_set_id) || value(patch_set, :id)

    if run_attempt_id && patch_set_id do
      attrs = %{
        run_attempt_id: run_attempt_id,
        patch_set_id: patch_set_id,
        planned_risk: classification.planned_risk,
        observed_risk: classification.observed_risk,
        reasons: classification.reasons,
        touched_risk_domains: classification.touched_risk_domains,
        required_review_kinds: classification.required_review_kinds,
        required_gate_stages: classification.required_gate_stages
      }

      upsert_assessment(attrs)
    end
  end

  defp upsert_assessment(attrs) do
    existing =
      RiskAssessment
      |> Ash.read!(domain: Factory)
      |> Enum.find(
        &(&1.run_attempt_id == attrs.run_attempt_id and &1.patch_set_id == attrs.patch_set_id)
      )

    if existing do
      Ash.update!(existing, attrs, domain: Factory)
    else
      Ash.create!(RiskAssessment, attrs, domain: Factory)
    end
  end

  defp require_present(nil, category, message),
    do: {:error, %{"category" => category, "severity" => "blocking", "message" => message}}

  defp require_present(_value, _category, _message), do: :ok

  defp default_rule_reason(rule) do
    "matched risk rule for #{normalize_risk(get(rule, :observed_risk))} observed risk"
  end

  defp touched_domains(booleans) do
    booleans
    |> Enum.filter(fn {_key, value} -> value end)
    |> Enum.map(fn
      {"dependency_changes", true} -> "dependencies"
      {"migration_changes", true} -> "migrations"
      {"generated_file_changes", true} -> "generated_files"
      {"public_api_changes", true} -> "public_api"
      {"locked_path_touched", true} -> "locked_paths"
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_review_kinds(nil), do: [:general]

  defp normalize_review_kinds(kinds) do
    kinds
    |> List.wrap()
    |> Enum.map(&normalize_review_kind/1)
    |> Enum.filter(&(&1 in @review_kinds))
    |> case do
      [] -> [:general]
      valid -> valid
    end
  end

  defp normalize_review_kind(kind) when is_atom(kind), do: kind

  defp normalize_review_kind(kind) do
    kind
    |> to_string()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :general
  end

  defp normalize_risk(risk) do
    risk = to_string(risk)
    if Map.has_key?(@risk_order, risk), do: risk, else: "low"
  end

  defp max_risk(left, right) do
    if Map.fetch!(@risk_order, left) >= Map.fetch!(@risk_order, right), do: left, else: right
  end

  defp exceeds?(observed, planned),
    do: Map.fetch!(@risk_order, observed) > Map.fetch!(@risk_order, planned)

  defp plural_change_key("dependency_change"), do: "dependency_changes"
  defp plural_change_key("migration_change"), do: "migration_changes"
  defp plural_change_key("generated_file_change"), do: "generated_file_changes"
  defp plural_change_key("public_api_change"), do: "public_api_changes"
  defp plural_change_key(key), do: key

  defp dependency_path?(path),
    do:
      path in [
        "mix.exs",
        "mix.lock",
        "package.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock"
      ]

  defp migration_path?(path), do: String.starts_with?(path, "priv/repo/migrations/")

  defp generated_path?(path),
    do: String.contains?(path, "generated") or String.starts_with?(path, "priv/static/")

  defp public_api_path?(path),
    do: String.ends_with?(path, "_api.ex") or String.contains?(path, "/api/")

  defp matches_any?(_path, []), do: false
  defp matches_any?(path, globs), do: Enum.any?(globs, &glob_match?(path, &1))

  defp glob_match?(path, glob) do
    glob
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("^#{&1}$"))
    |> Regex.match?(path)
  end

  defp evidence_refs(nil), do: []
  defp evidence_refs(patch_set), do: Enum.reject([value(patch_set, :patch_ref)], &is_nil/1)

  defp digest(classification) do
    encoded = :erlang.term_to_binary(classification)
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
  end

  defp get(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp get(_value, _key), do: nil

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
