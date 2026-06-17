defmodule Conveyor.PlanAuditor do
  @moduledoc """
  Scores normalized plan readiness and persists deterministic `PlanAudit` records.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.PlanAudit
  alias Conveyor.Traceability

  @score_keys [
    "clarity",
    "acceptance_coverage",
    "testability",
    "traceability",
    "architecture",
    "autonomy_readiness"
  ]

  @vague_terms [
    "better",
    "fast",
    "improve",
    "nice",
    "robust",
    "simple",
    "user-friendly",
    "etc",
    "as needed",
    "tbd",
    "todo"
  ]

  @phase_one_autonomy ["L0", "L1", "L2"]

  defmodule Result do
    @moduledoc "Computed audit scores, findings, decision, and persisted record."

    @type t :: %__MODULE__{
            audit: struct(),
            score: non_neg_integer(),
            scores: map(),
            decision: :ready | :needs_clarification | :blocked,
            findings: [map()],
            coverage_summary: map()
          }

    @enforce_keys [:audit, :score, :scores, :decision, :findings, :coverage_summary]
    defstruct [:audit, :score, :scores, :decision, :findings, :coverage_summary]
  end

  @spec audit_plan!(struct()) :: Result.t()
  def audit_plan!(%Plan{} = plan) do
    traceability = Traceability.analyze_plan!(plan)
    contract = plan.normalized_contract || %{}
    audit_inputs = audit_inputs(contract, traceability)
    scores = scores(audit_inputs)
    score = aggregate_score(scores)

    findings =
      (traceability.findings ++ audit_inputs.findings)
      |> Enum.uniq_by(&{&1["severity"], &1["category"], &1["message"]})
      |> Enum.sort_by(& &1["message"])

    decision = decision(score, findings)
    coverage_summary = coverage_summary(traceability.coverage_summary, scores, audit_inputs)

    audit =
      Ash.create!(
        PlanAudit,
        %{
          plan_id: plan.id,
          score: score,
          decision: decision,
          findings: findings,
          coverage_summary: coverage_summary
        },
        domain: Factory
      )

    %Result{
      audit: audit,
      score: score,
      scores: scores,
      decision: decision,
      findings: findings,
      coverage_summary: coverage_summary
    }
  end

  defp audit_inputs(contract, traceability) do
    requirements = Map.get(contract, "requirements", [])
    acceptance_criteria = Map.get(contract, "acceptance_criteria", [])
    verification_commands = Map.get(contract, "verification_commands", [])
    decisions = Map.get(contract, "decisions", [])
    slices = Map.get(contract, "slices", [])

    findings =
      []
      |> Kernel.++(clarity_findings(contract, requirements))
      |> Kernel.++(acceptance_findings(traceability.requirement_map))
      |> Kernel.++(testability_findings(acceptance_criteria))
      |> Kernel.++(verification_command_findings(verification_commands))
      |> Kernel.++(architecture_findings(decisions))
      |> Kernel.++(autonomy_findings(slices))

    %{
      requirements: requirements,
      acceptance_criteria: acceptance_criteria,
      verification_commands: verification_commands,
      decisions: decisions,
      slices: slices,
      traceability: traceability,
      findings: findings
    }
  end

  defp scores(inputs) do
    %{
      "clarity" => clarity_score(inputs),
      "acceptance_coverage" => acceptance_coverage_score(inputs.traceability),
      "testability" => testability_score(inputs),
      "traceability" => inputs.traceability.coverage_summary["traceability_percent"],
      "architecture" => architecture_score(inputs),
      "autonomy_readiness" => autonomy_readiness_score(inputs)
    }
  end

  defp clarity_score(inputs) do
    if Enum.any?(inputs.findings, &(&1["category"] == "brief" and &1["message"] =~ "wording")),
      do: 60,
      else: 100
  end

  defp acceptance_coverage_score(traceability) do
    summary = traceability.coverage_summary["requirements"]
    percent(summary["with_acceptance_criteria"], summary["total"])
  end

  defp testability_score(inputs) do
    acceptance_score =
      percent(
        Enum.count(inputs.acceptance_criteria, &(string_list(&1, "required_test_refs") != [])),
        length(inputs.acceptance_criteria)
      )

    command_score = if inputs.verification_commands == [], do: 0, else: 100
    round((acceptance_score + command_score) / 2)
  end

  defp architecture_score(inputs) do
    if Enum.any?(inputs.findings, &(&1["message"] =~ "unresolved architecture decision")),
      do: 50,
      else: 100
  end

  defp autonomy_readiness_score(inputs) do
    ready =
      Enum.count(inputs.slices, fn slice ->
        string_list(slice, "likely_files") != [] and
          Map.get(slice, "autonomy_ceiling") in @phase_one_autonomy
      end)

    percent(ready, length(inputs.slices))
  end

  defp aggregate_score(scores) do
    scores
    |> Map.take(@score_keys)
    |> Map.values()
    |> then(&(Enum.sum(&1) / length(&1)))
    |> round()
  end

  defp decision(score, findings) do
    cond do
      Enum.any?(findings, &(&1["severity"] == "blocking")) -> :blocked
      score < 80 -> :needs_clarification
      true -> :ready
    end
  end

  defp coverage_summary(traceability_summary, scores, inputs) do
    %{
      "scores" => scores,
      "traceability" => traceability_summary,
      "decision_inputs" => %{
        "requirements" => length(inputs.requirements),
        "acceptance_criteria" => length(inputs.acceptance_criteria),
        "verification_commands" => length(inputs.verification_commands),
        "decisions" => length(inputs.decisions),
        "slices" => length(inputs.slices)
      }
    }
  end

  defp clarity_findings(contract, requirements) do
    goal_finding =
      if vague?(Map.get(contract, "goal", "")) do
        [
          finding(
            "Plan goal uses unmeasurable wording.",
            [],
            "Rewrite the goal with measurable behavior."
          )
        ]
      else
        []
      end

    requirement_findings =
      requirements
      |> Enum.filter(&vague?(Map.get(&1, "text", "")))
      |> Enum.map(fn requirement ->
        key = Map.fetch!(requirement, "key")

        finding(
          "Requirement #{key} uses unmeasurable wording.",
          [key],
          "Rewrite #{key} with measurable behavior."
        )
      end)

    goal_finding ++ requirement_findings
  end

  defp acceptance_findings(requirement_map) do
    requirement_map
    |> Map.values()
    |> Enum.filter(&(&1["acceptance_criteria"] == []))
    |> Enum.map(fn requirement ->
      ref = requirement["requirement_ref"]

      finding(
        "Requirement #{ref} has no acceptance criteria.",
        [ref],
        "Add acceptance criteria that reference #{ref}."
      )
    end)
  end

  defp testability_findings(acceptance_criteria) do
    acceptance_criteria
    |> Enum.filter(&(string_list(&1, "required_test_refs") == []))
    |> Enum.map(fn criterion ->
      key = Map.get(criterion, "key") || Map.get(criterion, "id")

      finding(
        "Acceptance criterion #{key} has no required tests.",
        [key],
        "Add required_test_refs for #{key}."
      )
    end)
  end

  defp verification_command_findings([]) do
    [
      finding(
        "Plan has no verification commands.",
        [],
        "Add at least one reproducible verification command."
      )
    ]
  end

  defp verification_command_findings(commands) do
    commands
    |> Enum.filter(&(string_list(&1, "argv") == [] or is_nil(Map.get(&1, "profile"))))
    |> Enum.map(fn command ->
      key = Map.get(command, "key", "unknown")

      finding(
        "Verification command #{key} is not reproducible.",
        [key],
        "Give #{key} a profile and argv."
      )
    end)
  end

  defp architecture_findings(decisions) do
    decisions
    |> Enum.filter(fn decision ->
      vague?(Map.get(decision, "decision", "")) or vague?(Map.get(decision, "rationale", ""))
    end)
    |> Enum.map(fn decision ->
      key = Map.fetch!(decision, "key")

      finding(
        "Decision #{key} has an unresolved architecture decision.",
        [key],
        "Resolve #{key} with a concrete decision and rationale."
      )
    end)
  end

  defp autonomy_findings(slices) do
    slices
    |> Enum.flat_map(fn slice ->
      key = Map.fetch!(slice, "key")

      []
      |> maybe_add(
        string_list(slice, "likely_files") == [],
        finding(
          "Slice #{key} has no likely files for conflict prediction.",
          [key],
          "Add likely_files for #{key}."
        )
      )
      |> maybe_add(
        Map.get(slice, "autonomy_ceiling") not in @phase_one_autonomy,
        finding(
          "Slice #{key} exceeds Phase-1 autonomy readiness.",
          [key],
          "Lower #{key} autonomy_ceiling to L0, L1, or L2."
        )
      )
    end)
  end

  defp finding(message, artifact_refs, next_action_label) do
    %{
      "severity" => "blocking",
      "category" => "brief",
      "message" => message,
      "artifact_refs" => artifact_refs,
      "next_actions" => [
        %{
          "kind" => "edit_plan",
          "label" => next_action_label
        }
      ]
    }
  end

  defp maybe_add(findings, true, finding), do: [finding | findings]
  defp maybe_add(findings, false, _finding), do: findings

  defp vague?(text) do
    normalized = String.downcase(text)
    Enum.any?(@vague_terms, &String.contains?(normalized, &1))
  end

  defp string_list(map, key) do
    case Map.get(map, key) || Map.get(map, String.to_existing_atom(key)) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _ -> []
    end
  end

  defp percent(_count, 0), do: 100
  defp percent(count, total), do: round(count / total * 100)
end
